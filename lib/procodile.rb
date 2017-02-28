module Procodile

  def self.root
    File.expand_path('../../', __FILE__)
  end

  def self.bin_path
    File.join(root, 'bin', 'procodile')
  end

end

class String
  def color(color)
    "\e[#{color}m#{self}\e[0m"
  end
end
