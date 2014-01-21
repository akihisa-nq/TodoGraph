#!/usr/bin/ruby
# coding: utf-8

require "date"

module LifeMap
	MAX_DE=3
	MAX_DAY = 31
	MAX_MONTH = 12
	MAX_YEAR = 10000

	class RangeValue
		def initialize( index, de, maxval )
			@index = index
			@de = de
			@maxval = maxval
		end

		def integer?
			false
		end

		def to_f
			@maxval.to_f *  @index / @de.to_f + 0.5 / @de.to_f
		end

		def to_i
			val = @maxval
			MAX_DE.times do |i|
				if 2 ** (MAX_DE - i) == @de
					val += @index
					return val
				else
					val += 2 ** (MAX_DE - i)
				end
			end
			val += 1
			val
		end

		def eql?( obj )
			obj.kind_of?( RangeValue ) && @index == obj.index && @de == obj.de
		end

		def ==( obj )
			eql?( obj )
		end

		def self.index( val, maxval, de )
			val = val.to_f.to_i unless val.integer?
			((val - 1).to_f / (maxval.to_f / de.to_f)).to_i + 1
		end

		def text
			case @de
			when 1
				prefix=""
			when 2
				if index == 1
					prefix="前半"
				else
					prefix="後半"
				end
			when 4
				prefix="Q"
			when 8
				prefix="E"
			else
				prefix="S#{@de}_"
			end

			if @de > 2
				prefix += @index.to_s
			end

			prefix
		end

		def id_text
			if @de == 1
				"X" * ( Math.log( @maxval, 10 ) + 1 )
			else
				text
			end
		end

		attr_reader :index, :de
	end

	class Date
		include Comparable

		def initialize( year, month, day )
			@year = year || RangeValue.new( 1, 1, MAX_YEAR )
			@month = month || RangeValue.new( 1, 1, MAX_MONTH )
			@day = day || RangeValue.new( 1, 1, MAX_DAY )
		end

		def eql?( obj )
			year == obj.year && month == obj.month && day == obj.day
		end

		def ==( obj )
			eql?( obj )
		end

		def hash
			year.to_i * 10000 + month.to_i * 100 + day.to_i
		end

		def <=> obj
			data = [
				[ year.to_f, obj.year.to_f ],
				[ month.to_f, obj.month.to_f ],
				[ day.to_f, obj.day.to_f ]
			]

			ret = 0
			data.each do |v|
				if v[0] != v[1]
					ret = v[0] <=> v[1]
                    break
				end
			end

			ret
		end

		def diff
			y = year
			return MAX_YEAR * 365 unless y.integer?

			diff = 0
			m = month
			m = m.to_f.to_i

			d = day
			unless d.integer?
				if m == MAX_MONTH
					y += 1
					m = 1
					d = 1
				else
					m += 1
					d = 1
				end

				diff = -1
			end

			date = ::Date.new( y, m, d )
			ret = ( date + diff ) - ::Date.today

			ret
		end

		attr_reader :year, :month, :day
	end

	class Identifier
		def initialize( date, number )
			@date = date
			@number = number
		end

		def eql?( obj )
			date.eql?( obj.date ) && number == obj.number
		end

		def ==( obj )
			eql?( obj )
		end

		def hash
			number * 10000 * 100 * 100 + date.hash
		end

		attr_reader :date, :number
	end

	class Entry
		def initialize( id, uid, body, url, ids )
			@id = id
			@uid = uid
			@body = body
			@url = url
			@previous_ids = ids.clone.freeze
			@styles = {}
			@annotation = ""
		end

		def date
			@id.date
		end

		def number
			@id.number
		end

		attr_reader :id, :uid, :body, :url, :previous_ids, :styles
		attr_accessor :annotation
	end

	class TableReader
		POS = "(\\d+|X+|[QHE]\\d+)"

		def initialize( io )
			@io = io
		end

		def parse_num( num, maxval )
			case num
			when /X+/
				RangeValue.new( 1, 1, maxval )
			when /E(\d+)/
				RangeValue.new( $1.to_i, 8, maxval )
			when /Q(\d+)/
				RangeValue.new( $1.to_i, 4, maxval )
			when /H(\d+)/
				RangeValue.new( $1.to_i, 2, maxval )
			else
				num.to_i
			end
		end

		def read_next_entry
			ids = []
			body = ""
			url = ""

			loop do
				line = @io.gets
				case line
				when /^[\r\n]*$/, nil
					break
				when /^=(\d+|X+)\/#{POS}\/#{POS}/
					@date = Date.new( parse_num($1, MAX_YEAR), parse_num($2, MAX_MONTH), parse_num($3, MAX_DAY) )
					@number = 1
				when /^id(\d+)/
					@uid = $1.to_i
				when /^<-\s*(\d+|X+)\/#{POS}\/#{POS}#(\d+)/
					date = Date.new( parse_num($1, MAX_YEAR), parse_num($2, MAX_MONTH), parse_num($3, MAX_DAY) )
					ids << Identifier.new( date, $4.to_i )
				when /^<-\s*id(\d+)/
					ids << $1.to_i
				when /^(http.*)/
					url = $1
				else
					body += line
				end
			end

			ret = nil
			unless body.empty?
				if @number.nil?
					name =""
					name = @io.path if @io.respond_to?( :path )
					$stderr << "No Date Error #{name} line #{@io.lineno}\n"
				else
					id = Identifier.new( @date, @number )
					ret = Entry.new( id, @uid, body, url, ids )

					@number += 1
					@uid = nil
				end
			end

			ret
		end

		def each_entry( &block )
			loop do
				entry = read_next_entry
				break unless entry
				block.call( entry )
			end
		end

		def self.read_entries( io )
			entries = []
			TableReader.new( io ).each_entry do |entry|
				entries << entry
			end
			entries
		end
	end

	class DataBase
		def initialize
			@table = {}
			@uid_table = {}
			@out_of_view = {}
			@date_styles = {}
		end

		def add( entry )
			@table[ entry.id ] = entry
			@uid_table[ entry.uid ] = entry if entry.uid
			self
		end

		def find( id )
			@table[ id ]
		end

		def find_by_uid( uid )
			@uid_table[ uid ]
		end

		def values
			@table.values
		end

		def dated_values
			unless @dated_table
				@dated_table = {}
				values.each do |entry|
					@dated_table[ entry.date ] ||= []
					if visible?( entry.id )
						@dated_table[ entry.date ] << entry
					end
				end
				@dated_table.delete_if do |key, value|
					value.empty?
				end
			end
			@dated_table
		end

		def visible?( id )
			not @out_of_view.include?( id )
		end

		def filter( &block )
			values.each do |value|
				if not block.call( value )
					@out_of_view[ value.id ] = true
				end
			end
			@dated_table = nil
		end

		def add_date_style( date, style, value )
			@date_styles[ date ] ||= {}
			@date_styles[ date ][ style ] = value
		end

		def get_date_styles( date )
			@date_styles[ date ] || {}
		end
	end

	class Counter
		def initialize
			reset(0)
		end

		def reset( start )
			@start = start
			@count = 0
		end

		def count_up
			@count += 1
		end

		attr_reader :start, :count
	end

	class DotWriter
		def initialize( io )
			@io = io
		end

		def write( db )
			# ヘッダー
			@io << <<-EOL
digraph Map
{
	fontname="MS Gothic"
	fontsize=11
	rankdir=LR
	graph [concentrate=true ranksep=1.3];
	node [shape="box" fontsize=11 fontname="MS Gothic" ];

			EOL

			indent = 1

			@io << "\t" * indent
			@io << "subgraph cluster_Z\n"
			@io << "\t" * indent
			@io << "{\n"
			indent += 1

			indent -= 1
			@io << "\t" * indent
			@io << "}\n\n"

			@prev_write_date = nil
			@mmm_id = 0
			@mmm_day = {}
			@mmm_month = {}
			(MAX_DE + 1).times do |i|
				de = 2 ** i
				@mmm_day[de] = Counter.new
				@mmm_month[de] = Counter.new
			end

			# エントリの追加
			sorted = db.dated_values.sort_by{|v| v[0]}
			sorted.each do |value|
				write_date( db, value[0], value[1], indent )
			end

			# フッター
			@io << <<-EOL
}
			EOL
		end

		def write_date( db, date, values, indent )
			# ヘッダ
			@io << "\t" * indent
			@io << "subgraph cluster_X#{date_id(date)}\n"
			@io << "\t" * indent
			@io << "{\n"
			indent += 1

			# スタイル
			db.get_date_styles( date ).each do |key, value|
				@io << "\t" * indent
				@io << %Q+#{key}="#{value}";\n+
			end

			# 日付確認
			if @prev_write_date
				# 分割系を更新
				(MAX_DE + 1).times do |i|
					de = 2 ** i
					if RangeValue.index( @prev_write_date.day, MAX_DAY, de ) != RangeValue.index( date.day, MAX_DAY, de )
						@mmm_day[de].reset( @mmm_id )
					end

					if RangeValue.index( @prev_write_date.month, MAX_MONTH, de ) != RangeValue.index( date.month, MAX_MONTH, de )
						@mmm_month[de].reset( @mmm_id )
					end
				end

				# 月が変わったら、日は全て更新
				if @prev_write_date.month.to_f.to_i != date.month.to_f.to_i
					(MAX_DE + 1).times do |i|
						de = 2 ** i
						@mmm_day[de].reset( @mmm_id )
					end
				end

				# 年が変わったら、月は全て更新
				if @prev_write_date.year.to_f.to_i != date.year.to_f.to_i
					(MAX_DE + 1).times do |i|
						de = 2 ** i
						@mmm_month[de].reset( @mmm_id )
					end
				end
			end
			@prev_write_date = date

			# ダミーノード
			count_up = false

			if not date.year.integer?
				dummy_node_count = 1
				count_up = true
			elsif not date.month.integer?
				counter = @mmm_month[date.month.de]

				if counter.count > 0
					dummy_node_count = counter.count
					base = counter.start
					kind = "Y#{date.month.de}"
				else
					dummy_node_count = 4
					count_up = true
				end
			elsif not date.day.integer?
				counter = @mmm_day[date.day.de]

				if counter.count > 0
					dummy_node_count = counter.count
					base = counter.start
					kind = "M#{date.day.de}"
				else
					dummy_node_count = 2
					count_up = true
				end
			else
				dummy_node_count = 1
				count_up = true
			end

			# カウント アップ時は強制的に D グループ
			if count_up
				kind = "D"
			end

			# ダミー ノードの追加
			dummy_node_count.times do |i|
				# ノード
				prev_node_name = "mmm"
				dummy_node_name = "mmm"

				if count_up
					prev_node_name += (@mmm_id - 1).to_s
					dummy_node_name += @mmm_id.to_s
				else
					dummy_node_name += "#{base}#{kind}_#{i}"

					if i == 0
						prev_node_name += base.to_s
					else
						prev_node_name += "#{base}#{kind}_#{i-1}"
					end
				end

				@io << "\t" * indent
				@io << %Q+#{dummy_node_name} [group=#{kind} label="" shape=circle color=gray]\n+
				@io << "\t" * indent

				# エッジ
				if @mmm_id > 0 or ! count_up
					@io << "#{prev_node_name} -> #{dummy_node_name} ["
					@io << "color=gray "
					if ! count_up && i == 0
						@io << "constraint=false"
					else
						@io << "weight=5 "
					end
					@io << "]\n"
				end

				# カウント
				if count_up
					(MAX_DE + 1).times do |i|
						de = 2 ** i
						@mmm_day[de].count_up
						@mmm_month[de].count_up
					end
					@mmm_id += 1
				end
			end

			# 中身
			@io << "\t" * indent
			@io << %Q+label="#{fmt_date(date)}"\n+
			@io << "\n"

			values.each do |entry|
				write_entry_body( entry, indent )
			end

			# ランク
			if date.day.integer?
				@io << "\t" * indent
				@io << "{ rank=same"
				values.each do |entry|
					@io << ";\n"
					@io << "\t" * indent
					@io << "#{node_id(entry)}"
				end
				@io << "}\n"
			end

			# フッター
			indent -= 1
			@io << "\t" * indent
			@io << "}\n"

			# 参照
			values.each do |entry|
				write_entry_refs( db, entry, indent )
			end

			# ダミーノードの復帰エッジ
			if ! count_up and dummy_node_count > 0
				@io << "\t" * indent
				@io << "mmm#{base}#{kind}_#{dummy_node_count - 1} -> mmm#{@mmm_id} [color=gray weight=4]\n"
			end

			@io << "\n"
		end

		def write_entry_body( entry, indent )
			@io << "\t" * indent
			@io << %Q+#{node_id( entry )} [+
			@io << %Q+ label="#{node_body(entry)}" +
			@io << %Q+ URL="#{entry.url}" + unless entry.url.empty?

			entry.styles.each do |key, value|
				@io << %Q+ #{key}="#{value}"+
			end

			@io << %Q+];\n+
		end

		def write_entry_refs( db, entry, indent )
			entry.previous_ids.each do |prev_id|
				unless prev_id.respond_to?( :date )
					obj = db.find_by_uid( prev_id )
					unless obj
						$stdout << "Article #{prev_id} Not Found (reference from #{node_id(entry)})\n"
						next
					end
					prev_id = obj.id
				end
				next unless db.visible?( prev_id )

				@io << "\t" * indent
				@io << node_id( prev_id )
				@io << " -> "
				@io << node_id( entry )
				@io << ";\n"
			end
		end

		def fmt_date( date )
			year = date.year.integer? ? "%04d" % date.year : "XXXX"
			month = date.month.integer? ? "%02d" % date.month : date.month.text
			day = date.day.integer? ? "%02d" % date.day : date.day.text

			str = ""
			str += year
			str += "/#{month}" unless month.empty?
			str += "/#{day}" unless day.empty?
			str
		end

		def date_id( date )
			year = date.year.integer? ? "%04d" % date.year : "XXXX"
			month = date.month.integer? ? "%02d" % date.month : date.month.id_text
			day = date.day.integer? ? "%02d" % date.day : date.day.id_text
			"#{year}#{month}#{day}"
		end

		def node_id( entry_or_id )
			if entry_or_id.respond_to?( :id )
				"n%d" % entry_or_id.id.hash
			else
				"n%d" % entry_or_id.hash
			end
		end

		def node_body( entry )
			body = ""

			unless entry.annotation.empty?
				body += "\\<"
				body += entry.annotation
				body += "\\>\\n"
			end

			body += "##{entry.number}"
			body += "\\n"
			body += entry.body.gsub( /[\r\n]+/, "\\n" )
			body
		end
	end
end

if __FILE__ == $0
	files = ARGV.shift
	out_path = ARGV.shift

	if File.extname(out_path) != ".dot"
		$stderr << "output file must be dot file\n"
		exit 1
	end

	db = LifeMap::DataBase.new
	Dir.glob( files ) do |name|
		File.open( name, "r:utf-8" ) do |file|
			reader = LifeMap::TableReader.new( file )
			reader.each_entry do |entry|
				db.add( entry )
			end
		end
	end

	db.filter do |entry|
		entry.date.diff >= -365
	end

	data = [
		[    -365, "#999999", "過去" ],
		[     -30, "#BBBBBB", "ずっと前" ],
		[      -7, "#DDDDDD", "ちょっと前" ],
		[       0, "#EEEEEE", "今" ],
		[       1, "#FFFFFF", "次" ],
		[       7, "#EEEE99", "その次" ],
		[      30, "#DDDD99", "ちょっと先" ],
		[     180, "#CCCC99", "ずっと先" ],
		[     365, "#BBBB99", "未来" ],
		[ 3 * 365, "skyblue", "目標" ],
	]

	db.dated_values.each do |date, values|
		data.reverse.each do |rule|
			if rule[0] <= date.diff
				values.each do |entry|
					entry.styles[ "style" ] = "filled"
					entry.styles[ "fillcolor" ] = rule[1]
					entry.annotation = rule[2]

					if rule[0] == 0
						entry.styles["penwidth"] = "3"
					end
				end

				db.add_date_style( date, "style", "filled" )
				db.add_date_style( date, "fillcolor", rule[1] )

				break
			end
		end
	end

	File.open( out_path, "w" ) do |file|
		LifeMap::DotWriter.new( file ).write( db )
	end
end
