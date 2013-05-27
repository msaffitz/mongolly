require 'mongo'
require 'logger'

class Mongo::MongoClient

  def snapshot_ebs(options={})
    options[:volume_tag] ||= 'mongolly'
    @mongolly_logger = options[:logger] || Logger.new(STDOUT)
    ec2 = AWS::EC2.new(access_key_id: options[:access_key_id], secret_access_key: options[:secret_access_key], region: options[:region])

    host, port = snapshot_ebs_target.split(':')
    instance = ec2.instances.find_from_address(host, port)

    @mongolly_logger.debug("Found target instance #{instance.id} from #{host}:#{port}")

    volumes = instance.volumes_with_tag(options[:volume_tag])

    @mongolly_logger.debug("Found target volumes #{volumes.map(&:id).join(', ')} ")

    raise RuntimeError "no suitable volumes found"  unless volumes.length > 0

    begin
      if volumes.length >= 1
        disable_profiling
        lock!
      end

      backup_key = (0...8).map{65.+(rand(25)).chr}.join
      volumes.each do |volume|
        @mongolly_logger.debug("Snapshotting #{volume.id} with tag #{backup_key}")
        snapshot = volume.create_snapshot("#{backup_key} #{Time.now} mongolly backup")
        snapshot.add_tag('created_at', value: Time.now)
        snapshot.add_tag('backup_key', value: backup_key)
      end

    ensure
      unlock!  if locked?
      enable_profiling
    end
  end

protected
  def snapshot_ebs_target
    host_port.join(':')
  end

  def disable_profiling
    @mongolly_logger.debug("Disabling profiling... ")

    @profiled_dbs = {}
    database_names.each do |db|
      begin
        unless self[db].profiling_level == :off
          @mongolly_logger.debug("Disabling profiling for #{db}, level #{self[db].profiling_level}")
          @profiled_dbs[db] = self[db].profiling_level
          self[db].profiling_level = :off
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
        self[db].profiling_level = level
      rescue Mongo::InvalidNSName
        @mongolly_logger.debug("Skipping database #{db} due to invalid name")
      end
    end
    return true
  end

end
