module Bringit
  module Util
    LINE_SEP = "\n".freeze

    def self.count_lines(string)
      case string[-1]
      when nil
        0
      when LINE_SEP
        string.count(LINE_SEP)
      else
        string.count(LINE_SEP) + 1
      end
    end
  end
end
