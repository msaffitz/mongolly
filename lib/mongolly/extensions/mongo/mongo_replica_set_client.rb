require 'mongo'

class Mongo::MongoReplicaSetClient

  def most_current_secondary(threshold = 0)
    replica = self['admin'].command( replSetGetStatus: 1 )
    secondaries = replica['members'].select { |m| m['state'] == 2 }.sort_by { |m| m['name'] }
    most_current = secondaries.first
    secondaries[1..-1].each do |secondary|
      if (secondary['optime'] - most_current['optime']) > threshold
        most_current = secondary
      end
    end
    @mongolly_logger.debug("Found most current secondary #{most_current['name']}")
    most_current['name']
  end

protected
  def snapshot_ebs_target(threshold = 0)
    most_current_secondary(threshold)
  end
end
