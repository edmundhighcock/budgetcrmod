
class CodeRunner::Budget
  # All transactions occur between two accounts. 
  # One of those accounts is always physical (e.g. bank account, loan, credit card)
  # and the other can be either physical or a virtual account of the users choice,
  # e.g. Food or Petrol or Energy, or maybe WeeklyBudget and LongTermBudget etc.
  def external_account
    return @external_account if @external_account
    ext_account = false
    unless @runner
      raise "No runner for " + data_line
    end
    Dir.chdir(@runner.root_folder) do
      chosen = false
      Hash.phoenix('account_choices.rb') do |choices_hash|
        if choices_hash[signature]
          chosen = choices_hash[signature][:external_account]
        elsif choices_hash[data_line] 
          #choices_hash[data_line][:external_account] = 
          #choices_hash[data_line][:external_account].to_sym #fixes earlier bug
          #choices_hash[data_line][:sub_account] = 
          #choices_hash[data_line][:sub_account].to_sym #fixes earlier bug
          chosen = choices_hash[data_line][:external_account]
          choices_hash[signature] = choices_hash[data_line]
          choices_hash.delete(data_line)
        elsif choices_hash[old_data_line]
          chosen = choices_hash[old_data_line][:external_account]
          choices_hash[signature] = choices_hash[old_data_line]
        end
      end
      return @external_account = chosen if chosen
      chosen = false
      sym = nil
      while not chosen
        Hash.phoenix('external_accounts.rb') do |account_hash|
          #account_hash.each{|k,v| v[:name] = v[:name].to_sym} #Fixes an earlier bug
          #choices = account_arr.size.times.map{|i| [i,account_arr[i][:name]]}
          choices = account_hash.map{|k,v| [v[:sym], k]}.to_h
          puts Terminal.default_colour
          puts
          puts "-" * data_line.size
          puts signature.inspect
          puts "-" * data_line.size
          puts
          puts "Account: " + account
          puts
          puts choices.inspect
          puts
          puts "Please choose from the above external accounts for this transaction."
          puts "If you wish to add a new account type 0. To quit type q"
          puts "To start again for this transaction, type z"
          while not chosen
            require 'io/console'
            choice = STDIN.getch
            if choice == "q"
              throw :quit_data_entry
            elsif choice == "0"
              puts "Please type the name of the new account"
              name = STDIN.gets.chomp.to_sym
              puts "Please enter a symbol to represent this account (e.g. digit, letter, punctuation)."
              sym = false
              until sym
                sym = STDIN.getch
                if choices.keys.include? sym
                  puts "This symbol is taken"
                  sym = false
                end
              end
              account_hash[name] = {name: name, sym: sym, sub_accounts: {}}
              #choices_hash[@id] = name
              chosen = name
            elsif choice == "z"
              chosen = false
              break
            elsif not choices.keys.include? choice
              puts "Error: this symbol does not correspond to an account"
            else
              chosen = choices[choice] #account_hash[choice][:name]
            end
          end
          #Hash.phoenix('account_choices.rb') do |choices_hash|
          #choices_hash[data_line] = {external_account: chosen}
          #end
        end
        ext_account = chosen
        next if not chosen
        chosen = false
        Hash.phoenix('external_accounts.rb') do |account_hash|
          #choices = account_arr.size.times.map{|i| [i,account_arr[i][:name]]}
          sub_accounts = account_hash[ext_account][:sub_accounts]
          sub_accounts.each{|k,v| v[:name] = v[:name].to_sym} #Fixes an earlier bug
          choices = sub_accounts.map{|k,v| [v[:sym], k]}.to_h
          puts "-" * data_line.size
          puts
          puts choices.inspect
          puts
          puts "Please choose from the above sub-accounts for this transaction."
          puts "If you wish to add a new sub account, type 0. To quit, type q"
          puts "To start again for this transaction, type z"
          while not chosen
            require 'io/console'
            choice = STDIN.getch
            if choice == "q"
              throw :quit_data_entry
            elsif choice == "0"
              puts "Please type the name of the new sub account"
              name = STDIN.gets.chomp.to_sym
              puts "Please enter a symbol to represent this account (e.g. digit, letter, punctuation)."
              sym = false
              until sym
                sym = STDIN.getch
                if choices.keys.include? sym
                  puts "This symbol is taken"
                  sym = false
                end
              end
              sub_accounts[name] = {name: name, sym: sym}
              #choices_hash[@id] = name
              chosen = name
            elsif choice == "z"
              chosen = false
              break
            elsif not choices.keys.include? choice
              puts "Error: this symbol does not correspond to a sub-account"
            else
              chosen = choices[choice] #sub_accounts[choice][:name]
            end
          end
        end
        next if not chosen
        Hash.phoenix('account_choices.rb') do |choices_hash|
          choices_hash[signature] = {external_account: ext_account, sub_account: chosen}
        end
      end #while not chosen

    end
    ext_account
  end
  # All transactions have a subaccount. For transactions between
  # physical accounts this will almost always be just 'Transfer'
  # or similar, but virtual accounts will have more meaningful
  # sub_accounts, e.g. Food might have Groceries, EatingOut
  # or WeeklyBudget might have Transport, Food, Clothes... depending
  # on the users preferred way of organising things.
  # The sub_accounts are primarily a labelling exercise, but done 
  # well can be very helpful in showing a breakdown of expenditure.
  def sub_account
    return @sub_account if @sub_account
    puts "SIGNATURE ", signature.inspect
    Dir.chdir(@runner.root_folder) do
      external_account until (
        choices = Hash.phoenix('account_choices.rb'){|choices_hash| choices_hash[signature]}
        p [choices, data_line]
      ) and choices[:sub_account]
      @sub_account = choices[:sub_account]
    end
  end
end
