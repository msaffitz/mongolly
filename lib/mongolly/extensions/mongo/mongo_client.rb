require 'mongo'

class Mongo::MongoClient

  def snapshot_ebs(options={})
    options[:volume_tag] ||= 'mongolly'
    ec2 = AWS::EC2.new(access_key_id: options[:access_key_id], secret_access_key: options[:secret_access_key], region: options[:region])

    instance = ec2.instances.find_from_address(*snapshot_ebs_target.split(':'))
    volumes = instance.volumes_with_tag(options[:volume_tag])

    raise RuntimeError "no suitable volumes found"  unless volumes.length > 0

    begin
      if volumes.length >= 1
        disable_profiling
        lock!
      end

      backup_key = (0...8).map{65.+(rand(25)).chr}.join
      volumes.each do |volume|
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
    @profiled_dbs = {}
    database_names.each do |db|
      begin
        @profiled_dbs[db] = self[db].profiling_level  unless self[db].profiling_level == :off
        self[db].profiling_level = :off
      rescue Mongo::InvalidNSName
      end
    end
  end

  def enable_profiling
    return false  if locked?
    return true  unless @profiled_dbs
    @profiled_dbs.each do |db,level|
      self[db].profiling_level = level  rescue Mongo::InvalidNSName
    end
    return true
  end

end
