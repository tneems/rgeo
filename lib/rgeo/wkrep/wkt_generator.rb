# -----------------------------------------------------------------------------
#
# Well-known text generator for RGeo
#
# -----------------------------------------------------------------------------

module RGeo
  module WKRep
    # This class provides the functionality of serializing a geometry as
    # WKT (well-known text) format. You may also customize the serializer
    # to generate PostGIS EWKT extensions to the output, or to follow the
    # Simple Features Specification 1.2 extensions for Z and M.
    #
    # To use this class, create an instance with the desired settings and
    # customizations, and call the generate method.
    #
    # === Configuration options
    #
    # The following options are recognized. These can be passed to the
    # constructor, or set on the object afterwards.
    #
    # [<tt>:tag_format</tt>]
    #   The format for tags. Possible values are <tt>:wkt11</tt>,
    #   indicating SFS 1.1 WKT (i.e. no Z or M markers in the tags) but
    #   with Z and/or M values added in if they are present;
    #   <tt>:wkt11_strict</tt>, indicating SFS 1.1 WKT with Z and M
    #   dropped from the output (since WKT strictly does not support
    #   the Z or M dimensions); <tt>:ewkt</tt>, indicating the PostGIS
    #   EWKT extensions (i.e. "M" appended to tag names if M but not
    #   Z is present); or <tt>:wkt12</tt>, indicating SFS 1.2 WKT
    #   tags that indicate the presence of Z and M in a separate token.
    #   Default is <tt>:wkt11</tt>.
    #   This option can also be specified as <tt>:type_format</tt>.
    # [<tt>:emit_ewkt_srid</tt>]
    #   If true, embed the SRID of the toplevel geometry. Available only
    #   if <tt>:tag_format</tt> is <tt>:ewkt</tt>. Default is false.
    # [<tt>:square_brackets</tt>]
    #   If true, uses square brackets rather than parentheses.
    #   Default is false.
    # [<tt>:convert_case</tt>]
    #   Possible values are <tt>:upper</tt>, which changes all letters
    #   in the output to ALL CAPS; <tt>:lower</tt>, which changes all
    #   letters to lower case; or nil, indicating no case changes from
    #   the default (which is not specified exactly, but is chosen by the
    #   generator to emphasize readability.) Default is nil.

    class WKTGenerator
      # Create and configure a WKT generator. See the WKTGenerator
      # documentation for the options that can be passed.

      def initialize(opts = {})
        @tag_format = opts[:tag_format] || opts[:type_format] || :wkt11
        @emit_ewkt_srid = @tag_format == :ewkt ?
          (opts[:emit_ewkt_srid] ? true : false) : nil
        @square_brackets = opts[:square_brackets] ? true : false
        @convert_case = opts[:convert_case]
      end

      # Returns the format for type tags. See WKTGenerator for details.
      attr_reader :tag_format
      alias type_format tag_format

      # Returns whether SRID is embedded. See WKTGenerator for details.
      def emit_ewkt_srid?
        @emit_ewkt_srid
      end

      # Returns whether square brackets rather than parens are output.
      # See WKTGenerator for details.
      def square_brackets?
        @square_brackets
      end

      # Returns the case for output. See WKTGenerator for details.
      attr_reader :convert_case

      def properties
        {
          "tag_format" => @tag_format.to_s,
          "emit_ewkt_srid" => @emit_ewkt_srid,
          "square_brackets" => @square_brackets,
          "convert_case" => @convert_case ? @convert_case.to_s : nil
        }
      end

      # Generate and return the WKT format for the given geometry object,
      # according to the current settings.

      def generate(obj)
        @begin_bracket = @square_brackets ? "[" : "("
        @end_bracket = @square_brackets ? "]" : ")"
        factory = obj.factory
        if @tag_format == :wkt11_strict
          @cur_support_z = nil
          @cur_support_m = nil
        else
          @cur_support_z = factory.property(:has_z_coordinate)
          @cur_support_m = factory.property(:has_m_coordinate)
        end
        str = generate_feature(obj, true)
        if @convert_case == :upper
          str.upcase
        elsif @convert_case == :lower
          str.downcase
        else
          str
        end
      end

      private

      def generate_feature(obj, toplevel = false)
        type = obj.geometry_type
        type = Feature::LineString if type.subtype_of?(Feature::LineString)
        tag = type.type_name
        if @tag_format == :ewkt
          tag << "M" if @cur_support_m && !@cur_support_z
          tag = "SRID=#{obj.srid};#{tag}" if toplevel && @emit_ewkt_srid
        elsif @tag_format == :wkt12
          if @cur_support_z
            if @cur_support_m
              tag << " ZM"
            else
              tag << " Z"
            end
          elsif @cur_support_m
            tag << " M"
          end
        end
        if type == Feature::Point
          "#{tag} #{generate_point(obj)}"
        elsif type == Feature::LineString
          "#{tag} #{generate_line_string(obj)}"
        elsif type == Feature::Polygon
          "#{tag} #{generate_polygon(obj)}"
        elsif type == Feature::GeometryCollection
          "#{tag} #{generate_geometry_collection(obj)}"
        elsif type == Feature::MultiPoint
          "#{tag} #{generate_multi_point(obj)}"
        elsif type == Feature::MultiLineString
          "#{tag} #{generate_multi_line_string(obj)}"
        elsif type == Feature::MultiPolygon
          "#{tag} #{generate_multi_polygon(obj)}"
        else
          raise Error::ParseError, "Unrecognized geometry type: #{type}"
        end
      end

      def generate_coords(obj)
        str = "#{obj.x} #{obj.y}"
        str << " #{obj.z}" if @cur_support_z
        str << " #{obj.m}" if @cur_support_m
        str
      end

      def generate_point(obj)
        "#{@begin_bracket}#{generate_coords(obj)}#{@end_bracket}"
      end

      def generate_line_string(obj)
        if obj.is_empty?
          "EMPTY"
        else
          "#{@begin_bracket}#{obj.points.map { |p| generate_coords(p) }.join(', ')}#{@end_bracket}"
        end
      end

      def generate_polygon(obj)
        if obj.is_empty?
          "EMPTY"
        else
          "#{@begin_bracket}#{([generate_line_string(obj.exterior_ring)] + obj.interior_rings.map { |r| generate_line_string(r) }).join(', ')}#{@end_bracket}"
        end
      end

      def generate_geometry_collection(obj)
        if obj.is_empty?
          "EMPTY"
        else
          "#{@begin_bracket}#{obj.map { |f| generate_feature(f) }.join(', ')}#{@end_bracket}"
        end
      end

      def generate_multi_point(obj)
        if obj.is_empty?
          "EMPTY"
        else
          "#{@begin_bracket}#{obj.map { |f| generate_point(f) }.join(', ')}#{@end_bracket}"
        end
      end

      def generate_multi_line_string(obj)
        if obj.is_empty?
          "EMPTY"
        else
          "#{@begin_bracket}#{obj.map { |f| generate_line_string(f) }.join(', ')}#{@end_bracket}"
        end
      end

      def generate_multi_polygon(obj)
        if obj.is_empty?
          "EMPTY"
        else
          "#{@begin_bracket}#{obj.map { |f| generate_polygon(f) }.join(', ')}#{@end_bracket}"
        end
      end
    end
  end
end
