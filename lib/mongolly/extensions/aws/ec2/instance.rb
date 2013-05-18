require 'aws-sdk'

class AWS::EC2::Instance

  def volumes_with_tag(key)
    volumes = []
    attachments.each do |name,attachment|
      next  unless attachment.status == :attached
      volume = attachment.volume
      volumes << volume  if volume.status == :in_use && volume.tags.has_key?(key)
    end
    volumes
  end

end
