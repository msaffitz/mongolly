require "mongo"

class BSON::Timestamp
  include Comparable

  def <=>(other)
    s = seconds <=> other.seconds
    return s  unless s == 0
    increment <=> other.increment
  end

  def -(other)
    seconds - other.seconds
  end

end
