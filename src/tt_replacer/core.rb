#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
begin
  require 'TT_Lib2/core.rb'
rescue LoadError => e
  module TT
    if @lib2_update.nil?
      url = 'http://www.thomthom.net/software/sketchup/tt_lib2/errors/not-installed'
      options = {
        :dialog_title => 'TT_Lib² Not Installed',
        :scrollable => false, :resizable => false, :left => 200, :top => 200
      }
      w = UI::WebDialog.new( options )
      w.set_size( 500, 300 )
      w.set_url( "#{url}?plugin=#{File.basename( __FILE__ )}" )
      w.show
      @lib2_update = w
    end
  end
end


#-------------------------------------------------------------------------------

if defined?( TT::Lib ) && TT::Lib.compatible?( '2.7.0', 'Component Replacer' )

module TT::Plugins::ComponentReplacer


  ### MENU & TOOLBARS ### ------------------------------------------------------

  unless file_loaded?( __FILE__ )
    m = TT.menu( 'Tools' )
    m.add_item('Component Replacer') { self.activate_tool }
  end


  ### MAIN SCRIPT ### ----------------------------------------------------------

  def self.activate_tool
    my_tool = CompDropper.new
    Sketchup.active_model.tools.push_tool(my_tool)
  end


  class CompDropper

    def initialize
      @picked = nil

      @c_dropper = TT::Cursor.get_id(:dropper)
      @c_dropper_err = TT::Cursor.get_id(:dropper_invalid)
    end

    def update_vcb
      Sketchup::set_status_text('Pick component to replace the selected. Press Ctrl to disable Scale to Fit')
    end

    def activate
      @picked = nil
      @pos = [0,0,0]
      @drawn = false
      update_vcb()
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_vcb()
    end

    def onMouseMove(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)

      if ph.best_picked != @picked
        @pos = [x,y,0]
        @picked = ph.best_picked
        view.invalidate
      end
    end

    def onLButtonUp(flags, x, y, view)
      ctrl = flags & COPY_MODIFIER_MASK == COPY_MODIFIER_MASK
      dont_scale = ctrl

      if is_instance(@picked)
        model = Sketchup.active_model
        replacement = get_definition(@picked)

        TT::Model.start_operation('Replace Components')

        new_selection = []
        for instance in model.selection.to_a
          next unless is_instance(instance)
          definition = get_definition(instance)
          next if definition == replacement

          #puts "\nBehavior: #{definition.behavior.is2d?}"
          #puts "2d: #{self.is_2d?(definition.bounds)}"
          #puts "2d: #{self.is_2d?(instance.bounds)}"
          #puts 'Bounds'
          #puts [definition.bounds.width,definition.bounds.height,definition.bounds.depth].inspect
          #puts [instance.bounds.width,instance.bounds.height,instance.bounds.depth].inspect
          #puts 'Transformations:'

          if self.is_2d?(replacement.bounds)
            # (!) All replacement instances must also be 2D
            next unless self.is_2d?(definition.bounds)

            # (!) Rotate and match the 2D boundingboxes
            if replacement.bounds.width == 0
              if definition.bounds.width  == 0
                sy = definition.bounds.height / instance.bounds.height
                sx = definition.bounds.depth  / instance.bounds.depth
              elsif instance.bounds.height == 0
                # (!) Rotate
                sy = definition.bounds.height / instance.bounds.width
                sx = definition.bounds.depth  / instance.bounds.depth
              elsif instance.bounds.depth  == 0
                # (!) Rotate
                sy = definition.bounds.height / instance.bounds.height
                sx = definition.bounds.depth  / instance.bounds.width
              end
            elsif replacement.bounds.height == 0
              if definition.bounds.width  == 0
                # (!) Rotate
                sy = definition.bounds.height / instance.bounds.height
                sx = definition.bounds.depth  / instance.bounds.depth
              elsif instance.bounds.height == 0
                sy = definition.bounds.height / instance.bounds.width
                sx = definition.bounds.depth  / instance.bounds.depth
              elsif instance.bounds.depth  == 0
                # (!) Rotate
                sy = definition.bounds.height / instance.bounds.height
                sx = definition.bounds.depth  / instance.bounds.width
              end
            elsif replacement.bounds.depth == 0
              if definition.bounds.width  == 0
                # (!) Rotate
                sy = definition.bounds.height / instance.bounds.height
                sx = definition.bounds.depth  / instance.bounds.depth
              elsif instance.bounds.height == 0
                # (!) Rotate
                sy = definition.bounds.height / instance.bounds.width
                sx = definition.bounds.depth  / instance.bounds.depth
              elsif instance.bounds.depth  == 0
                sy = definition.bounds.height / instance.bounds.height
                sx = definition.bounds.depth  / instance.bounds.width
              end
            end
          else
            # Process 3D Objects.
            next if self.is_2d?(definition.bounds)

            # Create new scaling from definition difference.
            dsx = definition.bounds.width  / replacement.bounds.width
            dsy = definition.bounds.height / replacement.bounds.height
            dsz = definition.bounds.depth  / replacement.bounds.depth
            dts = Geom::Transformation.scaling( dsx, dsy, dsz )

            # Account for local origin offset.
            pt1 = replacement.bounds.corner(0)
            pt2 = definition.bounds.corner(0)
            v1 = pt1.vector_to( ORIGIN )
            v2 = ORIGIN.vector_to( pt2 )
            t1 = Geom::Transformation.new( v1 )
            t2 = Geom::Transformation.new( v2 )

            # Compute transformation adjustment.
            t = instance.transformation
            #instance.transform!( t.inverse )
            #instance.transform!( t1 )
            #instance.transform!( dts )
            #instance.transform!( t2 )
            #instance.transform!( t )

            nt = t * t2 * dts * t1 * t.inverse

            # Replace instance
            if instance.is_a?( Sketchup::ComponentInstance )
              instance.definition = replacement
              unless dont_scale
                instance.transform!( nt )
              end
            else
              # Groups must be replaced differently.
              ents = instance.parent.entities
              if dont_scale
                tr = instance.transformation
              else
                tr = nt * instance.transformation
              end
              new_instance = ents.add_instance( replacement, tr )
              new_instance.material = instance.material
              instance.erase!
              new_selection << new_instance
            end
          end
        end # for
        model.selection.add( new_selection )

        model.commit_operation
        UI.refresh_inspectors
        #model.tools.pop_tool
      end
    end

    def draw(view)
      if is_instance(@picked)
        definition = get_definition(@picked)
        view.draw_text(@pos, definition.name)
        @drawn = true
      end
    end

    # Draw the geometry
    def draw_geometry(pt1, pt2, view)
      view.draw_line(pt1, pt2)
    end

    def onSetCursor
      if is_instance(@picked)
        UI.set_cursor(@c_dropper)
      else
        UI.set_cursor(@c_dropper_err)
      end
    end

    def is_instance(entity)
      return entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
    end

    def get_definition(instance)
      # ComponentInstance
      return instance.definition if instance.is_a?(Sketchup::ComponentInstance)
      # Group
      if instance.entities.parent.instances.include?(instance)
        return instance.entities.parent
      else
        Sketchup.active_model.definitions.each { |definition|
          return definition if definition.instances.include?(instance)
        }
      end
      return nil # Error. We should never exit here.
    end

    def is_2d?(bounds)
      return bounds.width == 0 || bounds.height == 0 || bounds.depth == 0
    end

  end # class


  ### DEBUG ### ----------------------------------------------------------------

  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::ComponentReplacer.reload
  #
  # @param [Boolean] tt_lib Reloads TT_Lib2 if +true+.
  #
  # @return [Integer] Number of files reloaded.
  # @since 1.0.0
  def self.reload( tt_lib = false )
    original_verbose = $VERBOSE
    $VERBOSE = nil
    TT::Lib.reload if tt_lib
    # Core file (this)
    load __FILE__
    # Supporting files
    if defined?( PATH ) && File.exist?( PATH )
      x = Dir.glob( File.join(PATH, '*.{rb,rbs}') ).each { |file|
        load file
      }
      x.length + 1
    else
      1
    end
  ensure
    $VERBOSE = original_verbose
  end

end # module

end # if TT_Lib

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------