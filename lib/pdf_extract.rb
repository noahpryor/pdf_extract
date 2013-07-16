require 'java'
require 'tesseract'
require 'docsplit'
require 'image_voodoo'
require 'json'
require 'open-uri'
class PageExtractor
	attr_accessor :page, :results, :items, :image_path, :pdf_path, :results
	def initialize(page)
		@image_path = page[:image_path]
		@pdf_path = page[:pdf_path]
		@items = page[:items]
		@page_num = page[:page] ||= 1
		@results = {}
	end

	def process
		items.each do |item|
			case item[:kind]
			when 'ocr' then extract_ocr(item)
			when 'table' then extract_table(item)
			end
		end

	end

	def extract_ocr(item)
		dimensions = item[:dimensions]
		@results[item[:name]] = ocr_text(crop_image(dimensions))	
	end

	def crop_image(d)
		new_image_name = "CR.png"
		ImageVoodoo.with_image(image_path) do |img|
			x1 = d[:x1]	
			x2 = d[:x2]
			y1 = d[:y1]
			y2 = d[:y2]
			img.with_crop(x1,y1,x2,y2) { |img2| img2.save new_image_name }
		end
		return new_image_name
	end

	def extract_table(item)
		table = run_tabula(item[:dimensions])
		@results[item[:name]] = lines_to_array(table)
	end

	def run_tabula(d)
	area = [d[:y1],d[:x1],d[:y2],d[:x2]].join(", ")
	table = `tabula --area='#{area}' #{pdf_path} --page=#{page_num}`
	return table
	end
	
	def lines_to_array(table)
	  table.lines.map(&:chomp).map { |l|
	    l.split(",")
	  }
	end

	def ocr_text(image_path,blacklist='|',language=:eng)
		e = Tesseract::Engine.new {|e|
		  e.language  = language
		  e.blacklist = blacklist
		}
		return e.text_for(image_path).strip
	end
end

class Hash
	def symbolize_keys!
	  keys.each do |key|
	    self[(key.to_sym rescue key) || key] = delete(key)
	  end
	  self
	end
end

class PDFextract
	attr_accessor :file_path, :results
	attr_accessor :options,:text_dir,:base_dir
	attr_accessor :image_dir, :output_dir, :pages

	def initialize(schema)
		schema.symbolize_keys!

		@base_dir = Time.now.to_i.to_s
		setup_folders(@base_dir)
		@text_dir = @base_dir+'/text_files'
		@image_dir = @base_dir+'/image_files'
		@output_dir = @base_dir+'/output'
		if schema[:file_url]
			@file_path = get_file_from_url(schema[:file_url])
		else
			@file_path = get_file_from_path(schema[:file_path])
			puts @file_path
		end
		@options = schema[:options] if schema[:options]
		@pages = schema[:pages] if schema[:options]
		@results = {}

	end
	def setup_folders(folder_name)
			`rm -r #{folder_name}` if Dir.exists? folder_name
			`mkdir #{folder_name}`
			`mkdir #{text_dir}`
			`mkdir #{output_dir}`
	end

	def get_file_from_url(file_url)
		file_data = open(file_url).read
		temp_file = open(@base_dir+"/temp-file.pdf","w")
		temp_file.write file_data
		temp_file.close
		return temp_file.path
	end
	def get_file_from_path(path)
		new_path = @base_dir+"/temp-file.pdf"
		`cp #{path} #{new_path}` 
		return new_path
	end

	def process
		remove_protection if options[:remove_protection] == true 
		results[:images] = pdf_to_image_files("all")
		results[:text] = convert_to_text if options[:extract_all_text] == true 
		process_pages
		cleanup
	end
	def cleanup
		`rm -r #{base_dir}`
	end
	def remove_protection
		#todo

	end
	
	def process_pages
		pages.each do |page|
			if page[:match] == "page_num"
				page_num = page[:page]
				page[:image_path] = image_dir+"/temp-file_#{page_num}.png"
				page[:pdf_path] = file_path
								
			end
			page_extractor = PageExtractor.new(page)
			page_extractor.process
			results[page_num] = page_extractor.results
		end

	end


	def convert_to_text(pages = "all")
		pdf_to_text_files(pages)
		text = {}
		#take the text from the pdf pages and load em into this shit
		Dir.glob(text_dir+"/*.txt").each do |file|  
			page_num = file.split("_")[-1].split(".")[0]
			text[page_num] = File.open(file).read 
		end
		puts text
		return text
	end
	def convert_to_image(pages = "all")
		pdf_to_image_files(pages)
		images = []
		Dir.glob(image_dir+"/*.png").each do |file|  
			images << file 
		end
	end

	def pdf_to_image_files(pages)
		Docsplit.extract_images(file_path,:output => image_dir, :format => [:png])
	end

	def pdf_to_text_files(pages)
	    Docsplit.extract_text(file_path, :output => text_dir,:pages => pages)
	end
	def extract_with_ocr(page_path,dimensions)
		engine = Tesseract::Engine.new(language: :eng)
		engine.image = page_path
		engine.select 1,34,59,281
		text = engine.text.strip
		dimensions[:result] = text 
		return text
	end
	def self.extract_ocr(image_path,coords)
		x = coords["x1"]
		y = coords["y1"]
		width = coords["x2"] - x
		height = coords["y2"] - y
		puts [x,y,width,height]
		engine = Tesseract::Engine.new(language: :eng)
		engine.image = 'document_560_1.png'
		engine.select x,y,width,height
		text = engine.text.strip
		return text
	end

	def self.example_schema 
		{
			file_path: "test_files/dream-may.pdf",
			options: {
				remove_protection: false,
				password: nil,
				extract_all_text: true,
				extract_text: []
			},
			pages: [{
				match: "page_num",
				page: 1,
				items: [
					{
						name: 'title',
						kind: 'ocr', #alternative is kind table
						dimensions:  {
							x1: 10,
							x2: 282,
							y1: 50,
							y2: 100
						}
					},
					{
						name: 'units_table',
						kind: 'table',
						dimensions: {
							x1: 0,
							x2: 265.73,
							y1: 184.94,
							y2: 233.84
						}
					}
				]
			}]
		}
	end

end

coords = '[{"x1":59,"y1":55,"x2":237,"y2":95,"width":178,"height":40,"id":0,"page":1}]'
parsed = JSON.parse(coords)
puts parsed[0]
puts PDFextract.extract_ocr("document_560_1.pdf",parsed[0])