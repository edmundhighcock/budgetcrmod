class String
	def latex_escape
		self.gsub(/(?<!\\)([%_&^])/, '\\\\\1')
	end
end

class Date
	attr_accessor :sortsign
	def -@
		#@sortsign ? @sortsign *= -1 : (@sortsign=-1)
		newdate = dup
		newdate.sortsign = -1
		newdate
	end
	alias  :oldcompare :<=>
  def <=>(other)
	 	oldres = oldcompare(other)
	  oldres *= -1 if @sortsign==-1	 and other.sortsign == -1
		oldres
	end
end

require 'date'
class CodeRunner
	class Budget < Run
		@code_long = "Budget Calculator"
		@uses_mpi = false
		@naming_pars = []
		@run_info = []
		@variables = [:data_file, :account]
		@excluded_sub_folders = []
		@modlet_required = false
		@defaults_file_name = "budget_defaults.rb"

		@code_module_folder = folder = File.dirname(File.expand_path(__FILE__)) # i.e. the directory this file is in
		
#		["05/07/2010",
#		   "DEB",
#		  "308760",
#		  "25387560",
#		  "ANGELSCD 0655",
#		  "",
#		  "11.50",
#			  "4506.80"]
#
		@component_results = [:date, :type, :sc, :ac, :description, :debit, :credit, :balance]	
		@results = [:data] + @component_results
		def generate_input_file
			FileUtils.cp @data_file.sub(/~/, ENV['HOME']), @directory + '/data.cvs'
		end
		DOUBLE_STRING=/"(?:\\\\|\\"|[^"\\]|\\[^"\\])*"/
		def process_directory_code_specific
			@status=:Complete
			data = File.read('data.cvs')
			data = data.split("\n").map do 	|line| 
				p matches = line.scan(Regexp.new("((?:#{DOUBLE_STRING}|[^,])*)(?:,|$)"))
				matches.flatten
			end
			pp data
			@data = data
			@data.shift
		end
		def print_out_line
			if @is_component
				sprintf("%4d. %10s %3s %6s %8s %-60s %8s %8s %8s", id, *rcp.component_results.map{|res| send(res)})
			else
				#pr = component_runs.sort_by{|r| r.id}
				"#{sprintf("%3d", @id)}. #{sprintf("%-20s", @account)} Start: #{start_date}   End: #{end_date}   Final Balance: #{final_balance} "
			end
		end
		def date_sorted_component
			@date_sorted_component ||= component_runs.sort_by{|r| r.id}
		end
		def end_date
			date_sorted_component[-1].date
		end
		def start_date
			date_sorted_component[0].date
		end
		def final_balance
			date_sorted_component[-1].balance
		end
		def parameter_transition(run)
		end
		def parameter_string
			""
		end
		
		def generate_component_runs
			@runner.cache[:data] ||= []
			@data.each do |dataset|
				next if @runner.cache[:data].include? dataset and Date.parse(dataset[0]) > Date.parse("1/1/2013")
				component = create_component
				rcp.component_results.each_with_index do |res,index|
					value = dataset[index]
#					ep value
					value = Date.parse value if res == :date
					value = value.to_f if [:credit, :debit, :balance].include? res
					component.set(res, value)
				end
				@runner.cache[:data].push dataset
				#component.account = @account
			end
		end
		def days_ago
#			sprintf("%04d%02d%02d", date.year, date.month, date.day).to_i
			- ((date.to_datetime.to_time.to_i - Time.now.to_i) / 24 / 3600).to_i
		end
		def idate
			date.to_datetime.to_time.to_i
		end
		def ds
			description
		end


		def self.sum_future(future_items, end_date)
			sum = future_items.inject(0) do |sum, (name, item)| 
				item = [item] unless item.kind_of? Array
				value = item.inject(0) do |value,info|
					value += info[:size] unless (Date.today > info[:date]) or (info[:date] > end_date) # add unless we have already passed that date
					value
				end
				rcp.excluding.include?(name) ? sum : sum + value
			end
			sum
		end

		def self.budget_expenditure(runner, budget, budget_info, start_date)
			dates = []
			expenditures = []
			budget_items = []
			date = budget_info[:end]||Date.today
			start_date = [(budget_info[:start]||start_date), start_date].max
			expenditure = 0
			items_temp = []
			items = runner.component_run_list.values.find_all{|r| r.budget == budget and r.in_date(budget_info)}
			#ep ['items', items]
			#ep ['budget', budget]
			counter = 0
			if not budget_info[:period]
				dates.push date
				budget_items.push items
				expenditures.push (items.map{|r| r.debit - r.credit}+[0]).sum
			else

				case budget_info[:period][1]
				when :month
					while date > start_date
						items_temp += items.find_all{|r| r.date == date}
						if date.mday == (budget_info[:monthday] or 1)
							counter +=1
							if counter % budget_info[:period][0] == 0
								expenditure = (items_temp.map{|r| r.debit - r.credit}+[0]).sum
								dates.push date
								expenditures.push expenditure
								budget_items.push items_temp
								items_temp = []
								expenditure = 0
							end
						end
						date-=1
					end
				when :day
					while date > start_date
						items_temp += items.find_all{|r| r.date == date}
						#expenditure += (budget_items[-1].map{|r| r.debit}+[0]).sum
						counter +=1
						if counter % budget_info[:period][0] == 0
							expenditure = (items_temp.map{|r| r.debit - r.credit}+[0]).sum
							dates.push date
							expenditures.push expenditure
							budget_items.push items_temp
							items_temp = []
							expenditure = 0
						end
						date-=1
					end
				end
			end

			[dates, expenditures, budget_items]

		end

		def self.sum_regular(regular_items, end_date)
			today = Date.today
			sum = regular_items.inject(0) do |sum, (name, item)|	
				item = [item] unless item.kind_of? Array
#			  ep item
				value = item.inject(0) do |value,info|
					finish = (info[:end] and info[:end] < end_date) ? info[:end] : end_date
					#today = (Time.now.to_i / (24.0*3600.0)).round
					 
					nunits = 0
					counter = info[:period][0] == 1 ? 0 : nil
					unless counter
					  date = today
						counter = 0
						case info[:period][1]
						when :month
							while date >= (info[:start] or Date.today)
								counter +=1 if date.mday == (info[:monthday] or 1)
								date -= 1
							end
						when :year
							while date >= (info[:start] or Date.today) 
								counter +=1 if date.yday == (info[:yearday] or 1)
								date -= 1
							end
						when :day
							while date > (info[:start] or Date.today)
								counter +=1
								date -= 1
							end
						end
					end
					date = today
					case info[:period][1]
					when :month
						#p date, info
						while date <= finish 
							if date.mday == (info[:monthday] or 1)
								nunits += 1 if counter % info[:period][0] == 0
								counter +=1 
							end
							date += 1
						end
					when :year
						while date <= finish
							if date.yday == (info[:yearday] or 1)
								nunits += 1 if counter % info[:period][0] == 0
								counter +=1
							end
							date += 1
						end
					when :day
						while date <= finish
							nunits += 1 if counter % info[:period][0] == 0
							counter +=1
							date += 1
						end
					end





					#nyears = (finish.year - today.year)
					#nmonths = nyears * 12 + (finish.month - today.month)
					#(puts "Number of Months: #{nmonths}"; @pnmonths=true) unless @pnmonths
					#ndays = nyears * 12 + (finish.yday - today.yday)
					#number = case info[:period][1]
									 #when :month
										 #(nmonths / info[:period][0]).ceil
									 #when :day
										 #(ndays / info[:period][0]).ceil
									 #end
				 	#value + number * info[:size]
					#eputs "Regular Expenditure Item: #{sprintf("%10s", name)} -- #{nunits} payments, total #{nunits * info[:size]}"
					value + nunits * info[:size]

				end
				(rcp.excluding? and rcp.excluding.include?(name)) ? sum : sum + value
			end
			sum
		end
		def self.predictable_component_ids(runner)
			#runner.instance_variable_set(:@component_run_list, {})
			#runner.instance_variable_set(:@component_ids, [])
			#runner.instance_variable_set(:@component_id, -1)
			#runner.run_list.each{|r| r.instance_variable_set(:@component_runs, [])}
			#runner.run_list.values.sort_by{|r| r.id}.each{|r| r.generate_component_runs}
			#runner.save_large_cache
		end
		def self.kit_time_format_x(kit)
			 kit.gp.timefmt = %["%s"]
			 kit.data.each{|dk| dk.gp.using = "1:2"}
			 kit.gp.xdata = "time"
			 kit.gp.format = %[x "%d %B %Y"]
			 kit.gp.xtics = "rotate by 340 offset 0,-0.5 #{24*3600*14}"
			 kit.gp.xtics = "rotate by 340 offset 0,-0.5 "
		end

		def self.print_budget(options={})
			@excluding = (options[:excluding] or [])
			runner = CodeRunner.fetch_runner(Y: Dir.pwd)
			puts "------------------------------"
			puts "        Budget Report"
			puts "------------------------------"
			balance = runner.component_run_list.values.sort_by{|r| [r.date, r.id]}.map{|r| r.balance}[-1]
			puts "Balance: #{balance}"
			end_date = Date.parse("01/10/2011")
		  puts "Regular Expenditure: #{total_regular = 	sum_regular(REGULAR_EXPENDITURE, end_date)}"
			puts "Future Expenditure: #{total_future =  sum_future(FUTURE_EXPENDITURE, end_date)}"
			puts "Total Expenditure:  #{total_expenditure = total_future + total_regular}"
			puts "Total Income:  #{total_incoming = sum_future(FUTURE_INCOME, end_date)}"
			total = balance + total_incoming - total_expenditure
			puts "Weekly Budget:  #{total / ((end_date.to_datetime.to_time.to_i - Time.now.to_i) / 3600 / 24 /7)}"
		end

		def self.budgets_with_averages(runner, budgets, start_date)
		 projected_budgets = budgets.dup
		 projected_budgets.each{|key,v| projected_budgets[key]=projected_budgets[key].dup}
		 projected_budgets.each do |budget, budget_info|
			 #budget_info = budgets[budget]
			 dates, expenditures, items = budget_expenditure(runner, budget, budget_info, start_date)
			 budget_info[:size] = expenditures.mean rescue 0.0
		 end
		 projected_budgets
		end

		def self.latex_budget_transfers(runner, budgets, options)
			numdays = options[:days]
"#{budgets.map{|budget, budget_info| 
	dates, expenditures, items = budget_expenditure(runner, budget, budget_info, Date.today - numdays)
	#ep ['budget', budget, dates, expenditures]
	kit = GraphKit.quick_create([dates.map{|d| d.to_time.to_i}, expenditures])
	kit.data.each{|dk| dk.gp.with="boxes"}
	kit.gp.style = "fill solid"
	kit.xlabel = nil
	kit.ylabel = "Expenditure"
	unless options[:transfers]
	 kits = budgets_with_averages(runner, {budget => budget_info}, Date.today - numdays).map{|budget, budget_info| 
		 #ep 'Budget is ', budget
		 kit2 = GraphKit.quick_create([
				[dates[0], dates[-1]].map{|d| d.to_time.to_i}, 
				[budget_info[:size], budget_info[:size]]
		 ])
		 kit2.data[0].gp.with = 'lp lw 4'
		 kit2
		}
		#$debug_gnuplot = true
		#kits.sum.gnuplot
		kit += kits.sum

	else
		kit.data[0].y.data.map!{|expen| expen*-1.0}
	end
	kit.title = "#{budget} Expenditure with average (Total = #{kit.data[0].y.data.sum})"
	kit_time_format_x(kit)
	#kit.gnuplot
	kit.gnuplot_write("#{budget}.eps")
	"\\begin{center}\\includegraphics[width=4.0in]{#{budget}.eps}\\vspace{1em}\\end{center}"
}.join("\n\n")
}"
		end

		def self.latex_report(options={})
			runner = CodeRunner.fetch_runner(Y: Dir.pwd, h: :component)
			numdays = options[:days]
			# Delete budgets that contain no items
			actual_budgets = BUDGETS.dup
			BUDGETS.keys.each do |budget|
				actual_budgets.delete(budget) if budget_expenditure(runner, budget, BUDGETS[budget], Date.today - numdays)[0].size == 0
			end
			#predictable_component_ids(runner)
			days_ahead = options[:days_ahead]
			runs = runner.component_run_list.values
			indateruns = runs.find_all{|r| r.days_ago < numdays}
			accounts = runs.map{|r| r.account}.uniq
			ep 'Accounts', accounts
		 projected_budgets = Hash[actual_budgets.dup.find_all{|k,v| v[:discretionary]}]
		 projected_budgets = budgets_with_averages(runner,projected_budgets, Date.today - numdays)
		 #projected_budgets.each{|key,v| projected_budgets[key]=projected_budgets[key].dup}
		 #projected_budgets.each do |budget, budget_info|
			 ##budget_info = budgets[budget]
			 #dates, expenditures, items = budget_expenditure(runner, budget, budget_info, Date.today - numdays)
			 #budget_info[:size] = expenditures.mean
		 #end
		 ep 'projected_budgets', projected_budgets
			File.open('report.tex', 'w') do |file|
				file.puts <<EOF
\\documentclass{article}
\\usepackage[cm]{fullpage}
\\usepackage{tabulary}
\\usepackage{graphicx}
%\\usepackage{hyperlink}
\\newcommand\\Tstrut{\\rule{0pt}{2.8ex}}
\\begin{document}
\\title{#{numdays}-day Budget Report}
\\maketitle
\\tableofcontents

\\section{Summary of Accounts}
#{accounts.map{|acc|
"\\subsection{#{acc}}
\\begin{tabulary}{0.8\\textwidth}{ r l}
Balance & #{runs.find_all{|r| r.account==acc}.sort_by{|r| 
	r.date
}[-1].balance} \\\\
Expenditure & #{runs.find_all{|r| r.account==acc && 
	r.days_ago < numdays
}.map{|r| 
	r.debit
}.sum} \\\\
Income & #{runs.find_all{|r| r.account==acc && 
	r.days_ago < numdays
}.map{|r| r.credit}.sum} \\\\
\\end{tabulary}"}.join("\n\n")
}

\\section{Graphs of Recent Balances}
#{accounts.map{|acc|
 balance = runs.find_all{|r| r.account==acc}.sort_by{|r| r.date }[-1].balance
 accshort = acc.gsub(/\s/, '')
 kit = runner.graphkit(['date.to_time.to_i', 'balance'], {conditions: "account == #{acc.inspect} and days_ago < #{numdays}", sort: 'date'})
 futuredates = (Date.today..Date.today+days_ahead).to_a
 #p ["Regtrans", REGULAR_TRANSFERS.values_at(*REGULAR_TRANSFERS.keys.find_all{|from,to| to == acc})]

 budgets = Hash[projected_budgets.find_all{|k,v| v[:account] == acc}]
 ep ['budgets', budgets]
 projection = futuredates.map{|date| balance - 
	 sum_regular(REGULAR_EXPENDITURE[acc], date) + 
	 sum_regular(REGULAR_INCOME[acc], date) -  
	 sum_regular(budgets, date) -  
	 sum_future(FUTURE_EXPENDITURE[acc], date) + 
	 sum_future(FUTURE_INCOME[acc], date) + 
	 (REGULAR_TRANSFERS.keys.find_all{|from,to| to == acc}.map{|key|
	 #p [acc, 'to', "key", key]
	 sum_regular( REGULAR_TRANSFERS[key], date)
 }.sum||0) - 
	 (REGULAR_TRANSFERS.keys.find_all{|from,to| from == acc}.map{|key|
	 #p [acc, 'from',"key", key]
	 sum_regular( REGULAR_TRANSFERS[key], date)
 }.sum||0)  
 }
 kit2 = GraphKit.quick_create([futuredates.map{|d| d.to_time.to_i}, projection])
 kit += kit2
 kit.title = "Balance for #{acc}"
 kit.xlabel = %['Date' offset 0,-2]
 kit.xlabel = nil
 kit.ylabel = "Balance"

 kit.data[0].gp.title = 'Previous'
 kit.data[1].gp.title = '0 GBP Discretionary'
 kit.data[1].gp.title = 'Projection'
 kit.data.each{|dk| dk.gp.with = "lp"}

 kit_time_format_x(kit)

 (kit).gnuplot_write("#{accshort}_balance.eps", size: "4.0in,3.0in")
 "\\begin{center}\\includegraphics[width=4.0in]{#{accshort}_balance.eps}\\end{center}"
}.join("\n\n")
}


\\section{Budget Expenditure}
#{latex_budget_transfers(runner,actual_budgets, options)}

\\section{Transfers}
#{latex_budget_transfers(runner, TRANSFERS, options.dup.absorb({transfers: true}))}



\\section{Budget Resolutions}

This section sums items from budgets drawn from an alternate account, i.e. it determines how much should be transferred from one account to another as a result of expenditure from a given budget.

#{actual_budgets.map{|budget, budget_info|

"\\subsection{#{budget} }
		\\setlength{\\parindent}{0cm}\n\n\\begin{tabulary}{0.99\\textwidth}{r l}
			%\\hline
			Account Owed & Amount  \\\\
			\\hline
			\\Tstrut
  #{budget_items = indateruns.find_all{|r| r.budget == budget}
    alternate_accounts = budget_items.map{|r| r.account}.uniq - [budget_info[:account]]
		alternate_accounts.map{|acc|
			alternate_items = budget_items.find_all{|r| r.account == acc}
			total = alternate_items.map{|r| r.debit - r.credit}.sum
			"#{acc} & #{total} \\\\"
		}.join("\n\n")
	}

			\\\\
			\\hline
			\\end{tabulary}
			\\normalsize
			\\vspace{1em}\n\n

#{	alternate_accounts.map{|acc|
			alternate_items = budget_items.find_all{|r| r.account == acc}
			alternate_items.pieces((alternate_items.size.to_f/50.to_f).ceil).map{|piece|
			"\\footnotesize\\setlength{\\parindent}{0cm}\n\n\\begin{tabulary}{0.99\\textwidth}{ #{"c " * 4 + " L " + " r " * 3 }}
			    #{budget}: & #{budget_info[:account]} & owes & #{acc} &&&&\\\\
					\\hline

					\\Tstrut

					#{piece.map{|r| 
					([:id] + rcp.component_results - [:sc]).map{|res| 
							r.send(res).to_s.latex_escape
					#rcp.component_results.map{|res| r.send(res).to_s.gsub(/(.{20})/, '\1\\\\\\\\').latex_escape
						}.join(" & ")
					}.join("\\\\\n")
					}
			\\end{tabulary}\\normalsize"}.join("\n\n")
		}.join("\n\n")}
"
}.join("\n\n")
}



\\section{Budget and Transfer Breakdown}
#{(TRANSFERS + actual_budgets).map{|budget, budget_info| 
	dates, expenditures, budget_items = budget_expenditure(runner, budget, budget_info, Date.today - numdays)
	pp budget, budget_items.map{|items| items.map{|i| i.date.to_s}}
	"\\subsection{#{budget}}" + 
		budget_items.zip(dates, expenditures).map{|items, date, expenditure|
		if items.size > 0
			"
			\\footnotesize
			\\setlength{\\parindent}{0cm}\n\n\\begin{tabulary}{0.99\\textwidth}{ #{"c " * 4 + " L " + " r " * 2 }}
			%\\hline
			& #{date.to_s.latex_escape} & & & Total & #{expenditure} &  \\\\
			\\hline
			\\Tstrut
				#{items.map{|r| 
						([:id] + rcp.component_results - [:sc, :balance]).map{|res| 
								r.send(res).to_s.latex_escape
							}.join(" & ")
						}.join("\\\\\n")
					}
			\\\\
			\\hline
			\\end{tabulary}
			\\normalsize
			\\vspace{1em}\n\n"
		else 
			""
		end
	}.join("\n\n")
}.join("\n\n")
}



\\section{Recent Transactions}
#{accounts.map{|acc| 
	"\\subsection{#{acc}}
\\footnotesize
#{all = runs.find_all{|r|  r.account == acc and r.days_ago < numdays}.sort_by{|r| [r.date, r.id]}.reverse
ep ['acc', acc, 'ids', all.map{|r| r.id}, 'size', all.size]
all.pieces((all.size.to_f/50.to_f).ceil).map{|piece|
"\\setlength{\\parindent}{0cm}\n\n\\begin{tabulary}{0.99\\textwidth}{ #{"c " * 4 + " L " + " r " * 3 + "l"}}
		#{piece.map{|r| 
	  ([:id] + rcp.component_results - [:sc] + [:budget]).map{|res| r.send(res).to_s.latex_escape
	  #rcp.component_results.map{|res| r.send(res).to_s.gsub(/(.{20})/, '\1\\\\\\\\').latex_escape
  }.join(" & ")
}.join("\\\\\n")}
\\end{tabulary}"}.join("\n\n")}"
}.join("\n\n")}
\\end{document}
EOF


			end
			system "latex report.tex && latex report.tex"
		end

	end # class Budget
end #class CodeRunner

p Dir.pwd
require Dir.pwd + '/local_customisations.rb'
