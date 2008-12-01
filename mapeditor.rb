#!/usr/bin/ruby
begin
	# In case you use Gosu via rubygems.
	require 'rubygems'
rescue LoadError
	# In case you don't.
end

require 'gosu'
include Gosu

module Screen
	Width = 640
	Height = 480
end

$LOAD_PATH.push 'lib/'
require 'vectormap'

# Layering of sprites
module ZOrder
	Background, Lines, Vertices, UI = 0, 40, 50, 100
end

class Game < Gosu::Window
	attr_reader :mapFile, :layers, :camera_x, :camera_y

	def initialize
		super(Screen::Width, Screen::Height, false)
		self.caption = "Kanzapanoid Map Editor"

		# Put the score here, as it is the environment that tracks this now
		@score = 0
		@font = Gosu::Font.new(self, Gosu::default_font_name, 20)

		# Scrolling is stored as the position of the top left corner of the screen.
		@camera_x, @camera_y = 0,0

		@mode = 0
		@mouseColors = [0xffffffff, 0xff00ff00, 0xff0000ff]

		@mapFile = ''

		@editor = MapEditor.new self
		@input = TextField.new self, 'Map Name?'
	end

	def update
		if button_down? Gosu::KbLeft then @camera_x -= 10 end
		if button_down? Gosu::KbRight then @camera_x += 10 end
		if button_down? Gosu::KbUp then @camera_y -= 10 end
		if button_down? Gosu::KbDown then @camera_y += 10 end
	end

	def draw
		self.draw_line(mouse_x, mouse_y, @mouseColors[@mode],
					   mouse_x + 20, mouse_y + 20, 0xffffffff,
					   ZOrder::UI + 10)
		@editor.draw
		@input.draw
	end

	def button_down(id)
		if @mode == 1
			if id == Gosu::KbEscape then close end
			if id == Gosu::MsLeft then @editor.click(mouse_x + @camera_x, mouse_y + @camera_y) end
			if id == Gosu::MsRight then @editor.undo_line end
			if id == self.char_to_button_id('c') then @editor.close_poly end
			if id == self.char_to_button_id('u') then @editor.undo_poly end
			if id == self.char_to_button_id('s') then @editor.map.save end
		elsif @mode == 0
			if id == Gosu::KbEscape then
				# Escape key will not be 'eaten' by text fields; use for deselecting.
				if self.text_input then
					self.text_input = nil
				else
					close
				end
			elsif id == Gosu::MsLeft then
				# Mouse click: Select text field based on mouse position.
				if @input.under_point?(mouse_x, mouse_y)
					self.text_input = @input 
					if self.text_input.text == @input.defaultText
						self.text_input.text = ''
					end
				else
					if self.text_input and self.text_input.text == ''
						self.text_input.text = @input.defaultText
					end
					self.text_input = nil 
				end
			elsif id == Gosu::KbReturn
				@mapFile = self.text_input.text if self.text_input
				@editor.map.open @mapFile
				self.text_input = nil 
			end
		end

		if id == Gosu::KbReturn
			if @mode == 1
				@mode = 0
			else
				@mode = 1
			end
		end
	end
end

module LineColor
	Error = 0xffcc3300
	Active = 0xff009933
	Inactive = 0xff0099cc
	Selected = 0xff00ff00
end

class MapEditor
	attr_reader :map

	def initialize(window)
		@window = window
		@map = VectorMap.new window, true
		@open_poly = nil
	end

	def draw
		@camera_x = @window.camera_x
		@camera_y = @window.camera_y

		@map.draw
		@map.polys.each do |poly|
			poly.draw @window, @open_poly
		end

		if @open_poly and @open_poly.vertices.last
			# This line goes from the mouse to the last vertex in the poly.
			@window.draw_line(@open_poly.vertices.last[0], @open_poly.vertices.last[1], LineColor::Active,
							  @window.mouse_x, @window.mouse_y, LineColor::Selected,
							  ZOrder::UI)

			# This line goes from the mouse to the first vertex in the poly.
			if @open_poly.vertices[-2]
				@window.draw_line(@open_poly.vertices.first[0], @open_poly.vertices.first[1], LineColor::Active,
								  @window.mouse_x, @window.mouse_y, LineColor::Selected,
								  ZOrder::UI)
			end

			# Draw a line that shows the actual shape of the poly if you close it,
			# but only draw it if there are more than two vertices in the poly.
			if @open_poly.vertices.size > 2
				@window.draw_line(@open_poly.vertices.first[0], @open_poly.vertices.first[1], LineColor::Active,
								  @open_poly.vertices.last[0], @open_poly.vertices.last[1], LineColor::Active,
								  ZOrder::Lines + 1)
			end
		end
	end

	def click(x, y)
		if !@open_poly
			@open_poly = @map.new_poly
		end

		@open_poly.add_vertex(x, y)
	end

	def undo_line; @open_poly.vertices.pop; end
	def undo_poly; @map.polys.pop; end
	def close_poly; @open_poly = nil; end
end

class TextField < Gosu::TextInput
	# Some constants that define our appearance.
	INACTIVE_COLOR  = 0x33000000
	ACTIVE_COLOR    = 0x99000000
	SELECTION_COLOR = 0x99000000
	CARET_COLOR     = 0x99ffffff
	PADDING = 5

	attr_reader :defaultText

	def initialize(window, defaultText)
		super()
		@window = window

		@x, @y = 10, 10
		@font = Gosu::Font.new(@window, Gosu::default_font_name, 20)
		@width = Screen::Width - (PADDING * 4)
		@height = @font.height

		@defaultText = defaultText
		self.text = @defaultText
	end
	
	def draw
		# Depending on whether this is the currently selected input or not, change the
		# background's color.
		if @window.text_input == self then
			background_color = ACTIVE_COLOR
		else
			background_color = INACTIVE_COLOR
		end
		@window.draw_quad(@x - PADDING,          @y - PADDING,           background_color,
						  @x + @width + PADDING, @y - PADDING,           background_color,
						  @x - PADDING,          @y + @height + PADDING, background_color,
						  @x + @width + PADDING, @y + @height + PADDING, background_color,
						  ZOrder::UI)

		# Calculate the position of the caret and the selection start.
		pos_x = @x + @font.text_width(self.text[0...self.caret_pos])
		sel_x = @x + @font.text_width(self.text[0...self.selection_start])

		# Draw the selection background, if any; if not, sel_x and pos_x will be
		# the same value, making this quad empty.
		@window.draw_quad(sel_x, @y,          SELECTION_COLOR,
						  pos_x, @y,          SELECTION_COLOR,
						  sel_x, @y + @height, SELECTION_COLOR,
						  pos_x, @y + @height, SELECTION_COLOR,
						  ZOrder::UI)

		# Draw the caret; again, only if this is the currently selected field.
		if @window.text_input == self then
			@window.draw_line(pos_x, @y,          CARET_COLOR,
							  pos_x, @y + @height, CARET_COLOR,
							  ZOrder::UI)
		end

		# Finally, draw the text itself!
		@font.draw(self.text, @x, @y, ZOrder::UI)
	end

	# Hit-test for selecting a text field with the mouse.
	def under_point?(mouse_x, mouse_y)
		mouse_x > @x - PADDING and mouse_x < @x + @width + PADDING and
		mouse_y > @y - PADDING and mouse_y < @y + @height + PADDING
	end
end

Game.new.show

