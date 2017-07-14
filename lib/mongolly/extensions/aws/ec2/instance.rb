require "aws-sdk"

class AWS::EC2::Instance

  def volumes_with_tag(key)
    volumes = []
    attachments.each do |_, attachment|
      next  unless attachment.status == :attached
      volume = attachment.volume
      volumes << volume if volume.status == :in_use && volume.tags.key?(key)
    end
    volumes
  end

end
