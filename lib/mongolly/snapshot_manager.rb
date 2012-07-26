require 'aws-sdk'

module Mongolly
  class SnapshotManager

    def self.take_snapshots(db, aws_key_id, aws_secret_key, volume_ids)
      unless db.locked?
        puts " ** Locking Database"
        db.lock!
      end

      begin
        ec2 = AWS::EC2.new(access_key_id: aws_key_id, secret_access_key: aws_secret_key)
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
        end
      end
    end
  end
end
