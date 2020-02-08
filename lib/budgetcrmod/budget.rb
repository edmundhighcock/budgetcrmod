require 'date'
class String
  def latex_escape
    self.gsub(/(?<!\\)([$%_&^#])/, '\\\\\1')
  end
  #alias :old_to_f :to_f
  #def to_f
  #gsub(/,/, '').old_to_f
  #end
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

    @code_module_folder = File.dirname(File.expand_path(__FILE__)) # i.e. the directory this file is in

    @component_results = [:date, :type, :sc, :ac, :description, :deposit, :withdrawal, :balance]	
    @results = [:date_i, :data, :data_line, :dataset, :description2, :given_withdrawal, :given_deposit] + @component_results
    @signature_fields = [:date,:description,:deposit,:withdrawal,:account]
    def generate_input_file
      FileUtils.cp @data_file.sub(/~/, ENV['HOME']), @directory + '/data.cvs'
    end
    def debit
      case @account_type
      when :Asset, :Expense
        deposit
      else
        withdrawal
      end
    end
    def credit
      case @account_type
      when :Asset, :Expense
        withdrawal
      else
        deposit
      end
    end
    DOUBLE_STRING=/"(?:\\\\|\\"|[^"\\]|\\[^"\\])*"/
    def process_directory_code_specific
      @status=:Complete
      data = File.read('data.cvs')
      #p ['encoding', data.encoding]
      #data.encode(Encoding::UTF_8)
      tries = 1 
      begin
        data = data.split(/\n\r|\r\n|\n|\r/)
      rescue
        #require 'ensure/encoding.rb'
        if tries > 0
          if tries==1
            #data.force_encoding('iso-8859-1')
            data = File.read('data.cvs', encoding: "ISO-8859-1")
            data = data.encode('utf-8')
          end
          tries-=1
          retry
        end
      end
      if data[0] =~ /^\d{2} \w{3} \d\d,/ # BarclayCard format
        data.unshift 'date,description,type,user,expensetype,withdrawal,withdrawal'
      end

      @first_line_string = data[0].dup
      data = data.map do 	|line| 
        matches = line.scan(Regexp.new("((?:#{DOUBLE_STRING}|[^,])*)(?:,|$)"))
        pp matches
        matches.flatten
      end
      #pp data
      @data = data
      @first_line = @data.shift.join(',')
      generate_component_runs
    end
    #def reversed?
    #case account_type(@account)
    #when :Asset
    #@first_line =~ /Debit.*Credit/
    #end
    #end
    def print_out_line
      if @is_component
        sprintf("%4d. %10s %10s %3s  %-40s %8s %8s %8s %8s %8s", id, account, *rcp.component_results.find_all{|r| r!=:ac and r!=:sc}.map{|res| send(res).to_s.gsub(/\s+/, ' ')}, external_account, sub_account)
      else
        #pr = component_runs.sort_by{|r| r.id}
        "#{sprintf("%3d", @id)}. #{sprintf("%-20s", @account)} Start: #{start_date}   End: #{end_date}   Final Balance: #{final_balance} "
      end
    end
    def date_sorted_component
      @date_sorted_component ||= component_runs.sort_by{|r| r.id}
    end
    def end_date
      date_sorted_component[-1].date rescue nil
    end
    def start_date
      date_sorted_component[0].date rescue nil
    end
    def final_balance
      date_sorted_component[-1].balance rescue nil
    end
    def parameter_transition(run)
    end
    def parameter_string
      ""
    end
    #def external_account
    #name = super
    #if ACCOUNT_INFO[name] and ACCOUNT_INFO[name][:currencies].size > 2
    #end
    #def sub_account
    #end

    def sub_account
      cache[:sub_account] ||= super
    end
    def external_account
      cache[:external_account] ||= super
    end

    #def external_account
    #(budget.to_s + '_' + sub_account.to_s).to_sym
    #end

    def csv_data_fields
      case @first_line_string
      when /Date,Type,Sort Code,Account Number,Description,In,Out,Balance/ # Old Lloyds Bank Format
        [:date, :type, :sc, :ac, :description, :deposit, :withdrawal, :balance]
      when /Transaction Date,Transaction Type,Sort Code,Account Number,Transaction Description,Debit Amount,Credit Amount,Balance/ # 2013 Lloyds Bank Format, NB they are using debit and credit as if the account is an equity account (when of course a bank account is really an asset)
        [:date, :type, :sc, :ac, :description, :withdrawal, :deposit, :balance]
      when /Date,Date entered,Reference,Description,Amount/ # Lloyds Credit Card statement
        [:date, :dummy, :dummy, :description, :withdrawal]
      when /date,description,type,user,expensetype,withdrawal,withdrawal/
        [:date,:description,:type,:dummy,:dummy, :withdrawal, :withdrawal]
      when /Datum,Transaktion,Kategori,Belopp,Saldo/ # Nordea.se privat, Belopp is positive when the asset increases
        [:date,:description,:dummy,:deposit,:balance]
      when /Bokföringsdatum,Transaktionsreferens,Mottagare,Belopp,Valuta/ # Forex.se privat, Belopp is positive when the asset increases
        [:date,:description,:dummy,:deposit,:dummy]
      when /Datum,Text,Belopp/ #Ecster Credit Card
        [:date,:description,:deposit]
      when /Effective Date,Entered Date,Transaction Description,Amount,Balance/ #QudosBank new format the first field is blank
        [:dummy,:date,:description,:deposit,:balance]
      when /Effective Date,Entered Date,Transaction Description,Amount/ #QudosBank, the first field is blank
        [:dummy,:date,:description,:deposit]
      when /Date,Amount,Currency,Description,"Payment Reference","Running Balance","Exchange Rate","Payer Name","Payee Name","Payee Account Number",Merchant/ #TransferWise
        [:date,:deposit,:dummy,:description,:dummy,:balance,:dummy,:dummy,:dummy,:dummy,:dummy]
      when /"TransferWise ID",Date,Amount,Currency,Description,"Payment Reference","Running Balance","Exchange From","Exchange To","Exchange Rate","Payer Name","Payee Name","Payee Account Number",Merchant,"Total fees"/ #TransferWise New
        [:dummy,:date,:deposit,:dummy,:description,:description2,:balance,:dummy,:dummy,:dummy,:dummy,:dummy,:dummy,:dummy,:dummy]
      end
    end

    #def withdrawn
    #@withdrawn||0.0
    #end

    def has_balance? 
      @has_balance ||= csv_data_fields.include? :balance
    end

    attr_accessor :dummy


    def set_zeroes
      @withdrawal||=0.0
      @deposit||=0.0
    end
    def generate_component_runs
      #puts Kernel.caller
      #p ['generate_component_runs', @component_runs.class, (@component_runs.size rescue nil), @runner.component_run_list.size, @directory]
      return if @component_runs and @component_runs.size > 0
      @runner.cache[:data] ||= []
      #reslts = rcp.component_results
      #if reversed?
      #reslts[5] = :withdrawal
      #reslts[6] = :deposit
      #end
      @data.each do |dataset|
        #next if @runner.cache[:data].include? dataset and Date.parse(dataset[0]) > Date.parse("1/1/2013")
        #next if @runner.component_run_list.map{|k,v| v.instance_variable_get(:@dataset)}.include? dataset # and Date.parse(dataset[0]) > Date.parse("1/1/2013")
        next if @first_line_string =~ /^Datum/ and dataset[1] =~ /Reservation/
        h = {}
        h[:withdrawal] = 0.0
        h[:deposit] = 0.0
        h[:account] = @account
        reslts = csv_data_fields
        reslts.each_with_index do |res,index|
          value = dataset[index]
          #ep value
          value = Date.parse value if res == :date
          if [:deposit, :withdrawal, :balance].include? res
            case @first_line_string
            when /^Datum/i # we are dealing with European numbers
              value = value.gsub(/[." ]/, '')
              value = value.sub(/[,]/, '.')
            else
              value = value.gsub(/[",]/, '')
            end
            next unless value =~ /\d/
            value = value.to_f 
          end
          #component.set(res, value)
          h[res] = value
        end
        h[:data_line] =  reslts.map{|r| h[r].to_s}.join(',')

        if h[:description2] and h[:description]
          h[:description] += ":" + h[:description2]
        end

        h[:given_withdrawal] = h[:withdrawal]
        h[:given_deposit] = h[:deposit]
        if h[:deposit] < 0.0 and h[:withdrawal] == 0.0
          h[:withdrawal] = -h[:deposit]
          h[:deposit] = 0.0
        end
        if h[:withdrawal] < 0.0 and h[:deposit] == 0.0
          h[:deposit] = -h[:withdrawal]
          h[:withdrawal] = 0.0
        end
        next if @runner.component_run_list.find{|k,v| 
          v.signature == rcp.signature_fields.map{|res| h[res]}
        } # and Date.parse(dataset[0]) > Date.parse("1/1/2013")

        component = create_component
        #component.set_zeroes
        h.each{|k,v| component.set(k,v)}
        ep 'Generating Component', @component_runs.size
        component.set(:dataset, dataset)
        component.date_i = component.date.to_datetime.to_time.to_i
        #if component.description2 and component.description
          #component.description += ":" + component.description2
        #end
        #if component.deposit < 0.0 and component.withdrawal == 0.0
          #component.withdrawal = -component.deposit
          #component.deposit = 0.0
        #end
        #@runner.cache[:data].push dataset
        #component.external_account; component.sub_account # Triggers interactive account choices
        #component.account = @account
      end
    end
    def days_ago(today = Date.today)
      - ((date.to_datetime.to_time.to_i - today.to_datetime.to_time.to_i) / 24 / 3600).to_i
    end
    def idate
      date.to_datetime.to_time.to_i
    end
    def ds
      description
    end
    def signature
      #[date,description,deposit,withdrawal,account]
      rcp.signature_fields.map{|res| send(res)}
    end

    def old_data_line # For backwards compatibility issues when csv formats change
      case @first_line_string
      when /Effective Date,Entered Date,Transaction Description,Amount,Balance/ #QudosBank new format the first field is blank
        data_line.sub(/,[^,]*?$/, '')
      else
        nil
      end
    end


    def self.predictable_component_ids(runner)
    end
    def self.kit_time_format_x(kit)
      kit.gp.timefmt = %["%s"]
      kit.data.each{|dk| dk.gp.using = "1:2"}
      kit.gp.xdata = "time"
      kit.gp.format = %[x "%d %B %Y"]
      kit.gp.format = [%[x "%b %Y"]]
      kit.gp.mxtics = "30"
      kit.gp.xtics = "rotate by 340 offset 0,-0.5 #{24*3600*14}"
      kit.gp.xtics = "rotate by 340 offset 0,-0.5 2629746"
    end

    require 'budgetcrmod/account_choices.rb'


  end # class Budget
end #class CodeRunner

p Dir.pwd
#require Dir.pwd + '/local_customisations.rb'
