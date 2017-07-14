module Mongolly
  class Shepherd
    def initialize(options = {})
      @options           = options
      @access_key_id     = options[:access_key_id]
      @secret_access_key = options[:secret_access_key]
      @region            = options[:region] || "us-east-1"
      @database          = options[:database]
      @db_username       = options[:db_username]
      @db_password       = options[:db_password]
      @dry_run           = options[:dry_run]
      @logger            = options[:logger] || Logger.new(STDOUT)
      @logger.level = case options[:log_level].strip
                      when "fatal"; then Logger::FATAL
                      when "error"; then Logger::ERROR
                      when "warn"; then Logger::WARN
                      when "debug"; then Logger::DEBUG
                      else Logger::INFO
                      end
    end

    def backup
      @logger.info "Starting backup..."
      connection.snapshot_ebs({ logger: @logger }.merge(@options))
      @logger.info "Backup complete."
    end

    def cleanup(age)
      @logger.info "Starting cleanup..."
      raise ArgumentError, "Must provide a Time object to cleanup" unless age.class <= Time

      ec2 = AWS::EC2.new(access_key_id: @access_key_id,
                         secret_access_key: @secret_access_key,
                         region: @region)

      @logger.debug "deleting snapshots older than #{age}}"
      ec2.snapshots.with_owner(:self).each do |snapshot|
        next if snapshot.tags[:created_at].nil? || snapshot.tags[:backup_key].nil?
        if Time.parse.utc(snapshot.tags[:created_at]) < age
          @logger.debug "deleting snapshot #{snapshot.id} tagged #{snapshot.tags[:backup_key]} created at #{snapshot.tags[:created_at]}, earlier than #{age}"
          snapshot.delete unless @dry_run
        end
      end
      @logger.info "Cleanup complete."
    end

    def connection
      db = if @database.is_a? Array
             @logger.debug "connecting to a replica set #{@database}"
             Mongo::MongoReplicaSetClient.new(@database)
           else
             @logger.debug "connecting to a single instance #{@database}"
             Mongo::MongoClient.new(*@database.split(":"))
           end
      if @db_username && @db_password
        db["admin"].authenticate(@db_username, @db_password)
      end
      db
    end
  end
end
