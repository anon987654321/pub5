module Master
  module UI
    class Face
      ASCII_MATRIX = [
        "    ________________________________________    ",
        "   /                                        \\   ",
        "  |      [o]                  [o]            |  ",
        "  |              \\    /                      |  ",
        "  |               ----                       |  ",
        "  |           -------------                  |  ",
        "   \\________________________________________/   ",
        "        |  |                    |  |            ",
        "        |__|                    |__|            "
      ].freeze

      def self.render
        ASCII_MATRIX.each { |line| puts line }
      end
    end
  end
end
