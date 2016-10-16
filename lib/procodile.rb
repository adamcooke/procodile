module Procodile
end

class String
  def color(color)
    "\e[#{color}m#{self}\e[0m"
  end
end
