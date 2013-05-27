require 'mongo'

class Mongo::MongoReplicaSetClient

  def most_current_secondary
    replica = self['admin'].command( replSetGetStatus: 1 )
    current = replica['members'].select { |m| m['state'] == 2 }.sort_by { |m| m['optime'] }.reverse.first['name']
    @mongolly_logger.debug("Found most current secondary #{current}")
    current
  end

protected
  def snapshot_ebs_target
    most_current_secondary
  end
end
