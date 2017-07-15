require "mongo"
require "logger"
require "net/ssh"
require "retries"

class Mongo::MongoClient
  MAX_DISABLE_BALANCER_WAIT = 60 * 8 # 8 Minutes
  REPLICA_SNAPSHOT_THRESHOLD = 60 * 5 # 5 Minutes
  REPLICA_SNAPSHOT_PREFER_HIDDEN = true
  DEFAULT_MONGO_PORT = 27017 # rubocop: disable Style/NumericLiterals

  def snapshot_ebs(options = {})
    @mongolly_dry_run = options[:dry_run] || false
    @mongolly_logger = options[:logger] || Logger.new(STDOUT)
    options[:volume_tag] ||= "mongolly"
    options[:backup_key] ||= (0...8).map { 65.+(rand(25)).chr }.join

    @ec2 = AWS::EC2.new(access_key_id: options[:access_key_id], secret_access_key: options[:secret_access_key], region: options[:region])

    if mongos?
      @mongolly_logger.info("Detected sharded cluster")
      with_disabled_balancing do
        with_config_server_stopped(options) do
          backup_instance(config_server, options)

          shards.each do |name, hosts|
            @mongolly_logger.debug("Found Shard #{name} with hosts #{hosts}.")
            replica_set_connection(hosts, options).snapshot_ebs(options)
          end
        end
      end
    else
      backup_instance(snapshot_ebs_target(REPLICA_SNAPSHOT_THRESHOLD, REPLICA_SNAPSHOT_PREFER_HIDDEN), options.merge(strict_connection: true))
    end
  end

  protected

  def snapshot_ebs_target(_threshold = nil, _prefer_hidden = nil)
    host_port.join(":")
  end

  def disable_balancing
    @mongolly_logger.debug "Disabling Shard Balancing"
    self["config"].collection("settings").update({ _id: "balancer" }, { "$set" => { stopped: true } }, upsert: true) unless @mongolly_dry_run
  end

  def enable_balancing
    @mongolly_logger.debug "Enabling Shard Balancing"
    retry_logger = proc do |_, attempt_number, total_delay|
      @mongolly_logger.debug "Error enabling balancing (config server not up?); retry attempt #{attempt_number}; #{total_delay} seconds have passed."
    end
    with_retries(max_tries: 5, handler: retry_logger, rescue: Mongo::OperationFailure, base_sleep_seconds: 5, max_sleep_seconds: 120) do
      self["config"].collection("settings").update({ _id: "balancer" }, { "$set" => { stopped: false } }, upsert: true) unless @mongolly_dry_run
    end
  end

  def balancer_active?
    self["config"].collection("locks").find(_id: "balancer", state: { "$ne" => 0 }).count > 0
  end

  def config_server
    unless @config_server
      @config_server = self["admin"].command(getCmdLineOpts: 1)["parsed"]["sharding"]["configDB"].split(",").sort.first.split(":").first
      @mongolly_logger.debug "Found config server #{@config_server}"
    end
    @config_server
  end

  def with_config_server_stopped(options = {})
    # Stop Config Server
    ssh_command(options[:config_server_ssh_user], config_server, options[:mongo_stop_command], options[:config_server_ssh_keypath])
    yield
  rescue => ex
    @mongolly_logger.error "Error with config server stopped: #{ex}"
  ensure
    # Start Config Server
    ssh_command(options[:config_server_ssh_user], config_server, options[:mongo_start_command], options[:config_server_ssh_keypath])
  end

  def with_disabled_balancing
    disable_balancing
    term_time = Time.now.utc + MAX_DISABLE_BALANCER_WAIT
    while !@mongolly_dry_run && (Time.now.utc < term_time) && balancer_active?
      @mongolly_logger.info "Balancer active, sleeping for 10s (#{(term_time - Time.now.utc).round}s remaining)"
      sleep 10
    end
    if !@mongolly_dry_run && balancer_active?
      raise "Unable to disable balancer within #{MAX_DISABLE_BALANCER_WAIT}s"
    end
    @mongolly_logger.debug "With shard balancing disabled..."
    yield
  rescue => ex
    @mongolly_logger.error "Error with disabled balancer: #{ex}"
  ensure
    enable_balancing
  end

  def with_database_locked
    @mongolly_logger.debug "Locking database..."
    disable_profiling
    lock! unless @mongolly_dry_run || locked?
    @mongolly_logger.debug "With database locked..."
    yield
  rescue => ex
    @mongolly_logger.error "Error with database locked: #{ex}"
  ensure
    @mongolly_logger.debug "Unlocking database..."
    unlock! if !@mongolly_dry_run && locked?
    enable_profiling
  end

  def disable_profiling
    @mongolly_logger.debug("Disabling profiling... ")

    @profiled_dbs = {}
    database_names.each do |db|
      begin
        unless self[db].profiling_level == :off
          @mongolly_logger.debug("Disabling profiling for #{db}, level #{self[db].profiling_level}")
          @profiled_dbs[db] = self[db].profiling_level
          self[db].profiling_level = :off unless @mongolly_dry_run
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

    @profiled_dbs.each do |db, level|
      begin
        @mongolly_logger.debug("Enabling profiling for #{db}, level #{level}")
        self[db].profiling_level = level unless @mongolly_dry_run
      rescue Mongo::InvalidNSName
        @mongolly_logger.debug("Skipping database #{db} due to invalid name")
      end
    end
    true
  end

  def shards
    shards = {}
    self["config"]["shards"].find.each do |shard|
      shards[shard["_id"]] = shard["host"].split("/")[1].split(",")
    end
    shards
  end

  def replica_set_connection(hosts, options)
    db = Mongo::MongoReplicaSetClient.new(hosts)
    db["admin"].authenticate(options[:db_username], options[:db_password]) if options[:db_username]
    db
  end

  def ssh_command(user, host, command, keypath = nil)
    @mongolly_logger.debug("Running #{command} on #{host} as #{user}")
    return if @mongolly_dry_run
    exit_code = nil
    output = ""
    Net::SSH.start(host, user.strip, keys: keypath) do |ssh|
      channel = ssh.open_channel do |ch|
        ch.request_pty
        ch.exec(command.strip) do |_, success|
          raise "Unable to exec #{command.strip} on #{host}" unless success
        end
      end
      channel.on_request("exit-status") do |_, data|
        exit_code = data.read_long
      end
      channel.on_extended_data do |_, _, data|
        output += data
      end
      ssh.loop
    end

    if exit_code != 0
      raise "Unable to exec #{command} on #{host}, #{output}"
    end
  end

  private

  def backup_instance(address, options)
    host, port = address.split(":")
    port ||= DEFAULT_MONGO_PORT

    # Ensure we're directly connected to the target node for backup
    # This prevents a subclassed replica set from still acting against the
    # primary
    if options[:strict_connection] && (self.host != host || self.port.to_i != port.to_i)
      return Mongo::MongoClient.new(host, port.to_i, slave_ok: true).snapshot_ebs(options)
    end

    instance = @ec2.instances.find_from_address(host, port)

    @mongolly_logger.info("Backing up instance #{instance.id} from #{host}:#{port}")

    volumes = instance.volumes_with_tag(options[:volume_tag])

    @mongolly_logger.debug("Found target volumes #{volumes.map(&:id).join(', ')} ")

    raise "no suitable volumes found" if volumes.empty?

    backup_block = proc do
      volumes.each do |volume|
        @mongolly_logger.debug("Snapshotting #{volume.id} with tag #{options[:backup_key]}")
        next if @mongolly_dry_run
        snapshot = volume.create_snapshot("#{options[:backup_key]} #{Time.now.utc} mongolly #{host}")
        snapshot.add_tag("created_at", value: Time.now.utc)
        snapshot.add_tag("backup_key", value: options[:backup_key])
      end
    end

    if volumes.length > 1
      with_database_locked(&backup_block)
    else
      backup_block.call
    end
  end

end
