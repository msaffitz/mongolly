require 'mongo'

class Mongo::MongoReplicaSetClient

  def most_current_secondary
    replica = self['admin'].command( replSetGetStatus: 1 )
    replica['members'].select { |m| m['state'] == 2 }.sort_by { |m| m['optime'] }.reverse.first['name']
  end

protected
  def snapshot_ebs_target
    most_current_secondary
  end
end
