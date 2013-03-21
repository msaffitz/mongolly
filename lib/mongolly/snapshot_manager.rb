require 'aws-sdk'

module Mongolly
  class SnapshotManager

    def self.take_snapshots(db, aws_key_id, aws_secret_key, region, volume_ids)
      profile_levels = {}

      unless db.locked?
        puts " ** Locking Database"
        db.database_names.each do |db_name|
          begin
            level = db[db_name].profiling_level
            if level != :off
              profile_levels[db_name] = level
              db[db_name].profiling_level = :off
            end
          rescue Mongo::InvalidNSName
            puts " ** Skiping #{db_name} with invalid database name"
          end
        end
        db.lock!
      end

      begin
        ec2 = AWS::EC2.new(access_key_id: aws_key_id, secret_access_key: aws_secret_key).regions[region]
        backup_key = (0...8).map{65.+(rand(25)).chr}.join

        puts " ** Starting Snapshot with key #{backup_key}"

        volume_ids.map{ |v| v.to_s.strip }.each do |volume_id|
          puts " ** Taking snapshot of volume #{volume_id}"
          volume = ec2.volumes[volume_id]
          raise RuntimeError.new("Volume #{volume_id} does not exist") unless volume.exists?

          snapshot = volume.create_snapshot("#{backup_key} #{Time.now} mongo backup")
          snapshot.add_tag('created_at', value: Time.now)
          snapshot.add_tag('backup_key', value: backup_key)
        end
      ensure
        if db.locked?
          puts " ** Unlocking Database"
          db.unlock!
          db.database_names.each do |db_name|
            begin
               level = profile_levels[db_name]
              unless level.nil? || level == :off
                puts " ** Setting #{db_name} profile level to #{level.to_s}"
                db[db_name].profiling_level = level
              end
            rescue Mongo::InvalidNSName
              puts " ** Skiping #{db_name} with invalid database name"
            end
          end
        end
      end
    end
  end
end
