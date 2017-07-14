require "mongo"

class Mongo::MongoReplicaSetClient

  def most_current_secondary(threshold = 0, prefer_hidden = true)
    replica = self["admin"].command(replSetGetStatus: 1)
    secondaries = replica["members"].select { |m| m["state"] == 2 }.sort_by { |m| [m["optime"], m["name"]] }
    most_current = secondaries.first

    hidden = self["local"]["system"]["replset"].find_one["members"].select { |mem| mem["hidden"] }.map { |mem| mem["host"] }

    if prefer_hidden && !hidden.include?(most_current["name"])
      secondaries[1..-1].each do |secondary|
        if hidden.include?(secondary["name"]) && (most_current["optime"] - secondary["optime"]) < threshold
          most_current = secondary
          break
        end
      end
    end

    @mongolly_logger.debug("Found most current secondary #{most_current['name']}, hidden: #{hidden.include? most_current['name']}")
    most_current["name"]
  end

  protected

  def snapshot_ebs_target(threshold = 0, prefer_hidden = true)
    most_current_secondary(threshold, prefer_hidden)
  end
end
