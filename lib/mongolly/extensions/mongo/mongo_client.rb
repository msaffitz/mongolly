require 'mongo'
require 'logger'
require 'net/ssh'
require 'retries'

require 'debugger'

class Mongo::MongoClient
  MAX_DISABLE_BALANCER_WAIT = 60*5 # 5 Minutes

  def snapshot_ebs(options={})

    @mongolly_dry_run = options[:dry_run] || false
    @mongolly_logger = options[:logger] || Logger.new(STDOUT)
    options[:volume_tag] ||= 'mongolly'
    options[:backup_key] ||= (0...8).map{65.+(rand(25)).chr}.join

    @ec2 = AWS::EC2.new(access_key_id: options[:access_key_id], secret_access_key: options[:secret_access_key], region: options[:region])

    if mongos?
      @mongolly_logger.info("Detected sharded cluster")
      with_disabled_balancing do
        stop_config_server(options[:config_server_ssh_user], options[:mongo_stop_command])

        backup_instance(config_server, options, false)

        shards.each do |name,hosts|
          @mongolly_logger.debug("Found Shard #{name} with hosts #{hosts}.")
          replica_set_connection(hosts, options).snapshot_ebs(options)
        end
        start_config_server(options[:config_server_ssh_user], options[:mongo_start_command])
      end
    else
      backup_instance(snapshot_ebs_target, options, true )
    end
  end

protected
  def snapshot_ebs_target
    host_port.join(':')
  end

  def backup_instance(address, options, lock = true)
    host, port = address.split(':')
    instance = @ec2.instances.find_from_address(host, port)

    @mongolly_logger.info("Backing up instance #{instance.id} from #{host}:#{port}")

    volumes = instance.volumes_with_tag(options[:volume_tag])

    @mongolly_logger.debug("Found target volumes #{volumes.map(&:id).join(', ')} ")

    raise RuntimeError.new "no suitable volumes found"  unless volumes.length > 0

    backup_block = proc do
      volumes.each do |volume|
        @mongolly_logger.debug("Snapshotting #{volume.id} with tag #{options[:backup_key]}")
        unless @mongolly_dry_run
          snapshot = volume.create_snapshot("#{options[:backup_key]} #{Time.now} mongolly #{host}")
          snapshot.add_tag('created_at', value: Time.now)
          snapshot.add_tag('backup_key', value: options[:backup_key])
        end
      end
    end

    if lock
      with_database_locked &backup_block
    else
      backup_block.call
    end
  end

  def disable_balancing
    @mongolly_logger.debug "Disabling Shard Balancing"
    self['config'].collection('settings').update({_id: 'balancer'}, {'$set' => {stopped: true}}, upsert: true)  unless @mongolly_dry_run
  end

  def enable_balancing
    @mongolly_logger.debug "Enabling Shard Balancing"
    retry_logger = Proc.new do |exception, attempt_number, total_delay|
      @mongolly_logger.debug "Error enabling balancing (config server not up?); retry attempt #{attempt_number}; #{total_delay} seconds have passed."
    end
    with_retries(max_tries: 5, handler: retry_logger, rescue: Mongo::OperationFailure, base_sleep_seconds: 5, max_sleep_seconds: 120) do
      self['config'].collection('settings').update({_id: 'balancer'}, {'$set' => {stopped: false}}, upsert: true)  unless @mongolly_dry_run
    end
  end

  def balancer_active?
    self['config'].collection('locks').find({_id: 'balancer'}).count > 1
  end

  def stop_config_server(user, stop_command)
    raise RuntimeError.new "mongo ssh user not specified"  unless user.to_s.strip != ''
    raise RuntimeError.new "mongo ssh user not specified"  unless stop_command.to_s.strip != ''
    @mongolly_logger.debug "Stopping config server #{config_server}"
    unless @mongolly_dry_run
      exit_code = nil
      output = ''
      Net::SSH.start(config_server, user.strip) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.request_pty
          ch.exec(stop_command.strip) do |ch, success|
            raise "Unable to stop config server on #{config_server}"  unless success
          end
        end
        channel.on_request("exit-status") do |ch,data|
          exit_code = data.read_long
        end
        channel.on_extended_data do |ch,type,data|
          output += data
        end
        ssh.loop
      end

      if exit_code != 0
        raise RuntimeError.new "Unable to stop config server, #{output}"
      end
    end
  end

  def start_config_server(user, start_command )
    raise RuntimeError.new "mongo ssh user not specified"  unless user.to_s.strip != ''
    raise RuntimeError.new "mongo ssh user not specified"  unless start_command.to_s.strip != ''
    @mongolly_logger.debug "Starting config server #{config_server}"
    unless @mongolly_dry_run
      exit_code = nil
      output = ''
      Net::SSH.start(config_server, user.strip) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.request_pty
          ch.exec(start_command.strip) do |ch, success|
            raise "Unable to start config server on #{config_server}"  unless success
          end
        end
        channel.on_request("exit-status") do |ch,data|
          exit_code = data.read_long
        end
        channel.on_extended_data do |ch,type,data|
          output += data
        end
        ssh.loop
      end

      if exit_code != 0
        raise RuntimeError.new "Unable to start config server, #{output}"
      end
    end
  end

  def config_server
    unless @config_server
      @config_server = self['admin'].command( { getCmdLineOpts: 1 } )["parsed"]["configdb"].split(",").sort.first.split(":").first
      @mongolly_logger.debug "Found config server #{@config_server}"
    end
    return @config_server
  end

  def with_disabled_balancing
    begin
      disable_balancing
      term_time = Time.now + MAX_DISABLE_BALANCER_WAIT
      while !@mongolly_dry_run && (Time.now < term_time) && balancer_active?
        @mongolly_logger.info "Balancer active, sleeping for 10s (#{(term_time - Time.now).round}s remaining)"
        sleep 10
      end
      if !@mongolly_dry_run && balancer_active?
        raise RuntimeError.new "unable to disable balancer within #{MAX_DISABLE_BALANCER_WAIT}s"
      end
      @mongolly_logger.debug "With shard balancing disabled..."
      yield
    ensure
      enable_balancing
    end
  end

  def with_database_locked
    begin
      @mongolly_logger.debug "Locking database..."
      disable_profiling
      lock!  unless @mongolly_dry_run || locked?
      @mongolly_logger.debug "With database locked..."
      yield
    ensure
      @mongolly_logger.debug "Unlocking database..."
      unlock!  if !@mongolly_dry_run && locked?
      enable_profiling
    end
  end

  def disable_profiling
    @mongolly_logger.debug("Disabling profiling... ")

    @profiled_dbs = {}
    database_names.each do |db|
      begin
        unless self[db].profiling_level == :off
          @mongolly_logger.debug("Disabling profiling for #{db}, level #{self[db].profiling_level}")
          @profiled_dbs[db] = self[db].profiling_level
          self[db].profiling_level = :off  unless @mongolly_dry_run
        end
      rescue Mongo::InvalidNSName
        @mongolly_logger.debug("Skipping database #{db} due to invalid name")
      end
    end
  end

  def enable_profiling
    if locked?
      @mongolly_logger.debug("Database locked, can't turn on profiling")
      return false
    end
    unless @profiled_dbs
      @monglly_logger.debug("No dbs in @profiled_dbs")
      return true
    end

    @profiled_dbs.each do |db,level|
      begin
        @mongolly_logger.debug("Enabling profiling for #{db}, level #{level}")
        self[db].profiling_level = level  unless @mongolly_dry_run
      rescue Mongo::InvalidNSName
        @mongolly_logger.debug("Skipping database #{db} due to invalid name")
      end
    end
    return true
  end

  def shards
    shards = {}
    self['config']['shards'].find().each do |shard|
      shards[shard['_id']] = shard['host'].split("/")[1].split(",")
    end
    shards
  end

  def replica_set_connection(hosts, options)
    db = Mongo::MongoReplicaSetClient.new(hosts)
    db['admin'].authenticate(options[:db_username], options[:db_password], true)
    return db
  end

end
