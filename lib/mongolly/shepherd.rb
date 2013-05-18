module Mongolly
  class Shepherd

    def initialize(options={})
      @access_key_id     = options[:access_key_id]
      @secret_access_key = options[:secret_access_key]
      @region            = options[:aws_region] || 'us-east-1'
      @database          = options[:database]
      @db_username       = options[:db_username]
      @db_password       = options[:db_password]
    end

    def backup
      connection.snapshot_ebs(access_key_id: @access_key_id, secret_access_key: @secret_access_key, region: @region)
    end

    def cleanup(age)
      raise ArgumentError.new("Must provide a Time object cleanup")  unless age.class <= Time

      ec2 = AWS::EC2.new(access_key_id: @access_key_id, secret_access_key: @secret_access_key, region: @region)

      ec2.snapshots.with_owner(:self).each do |snapshot|
        unless snapshot.tags[:created_at].nil? || snapshot.tags[:backup_key].nil?
          snapshot.delete  if Time.parse(snapshot.tags[:created_at]) < age
        end
      end
    end

    def connection
      db = if @database.is_a? Array
        Mongo::MongoReplicaSetClient.new(@database)
      else
        Mongo::MongoClient.new(*@database.split(':'))
      end
      db['admin'].authenticate(@db_username, @db_password, true)
      return db
    end
  end
end
