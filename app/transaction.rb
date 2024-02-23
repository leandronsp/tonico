require_relative 'database'

class Transaction
  class InvalidDataError < StandardError; end
  class InvalidLimitAmountError < StandardError; end
  class NotFoundError < StandardError; end

  def self.call(*args)
    new(*args).call
  end

  def initialize(account_id, amount, transaction_type, description)
    @account_id = account_id
    @amount = amount
    @transaction_type = transaction_type
    @description = description
  end

  def call
    result = {}

    raise InvalidDataError unless @account_id && @amount && @transaction_type && @description
    raise InvalidDataError if @description && @description.empty?
    raise InvalidDataError unless %w[d c].include?(@transaction_type)

    db.transaction do 
      account = db.exec_params(sql_select_account, [@account_id]).first
      raise NotFoundError unless account

      limit_amount = account['limit_amount'].to_i
      balance = account['balance'].to_i

      raise InvalidLimitAmountError if @transaction_type == 'd' && 
                                        reaching_limit?(balance, limit_amount, @amount)

      db.exec_params(sql_insert_transaction, 
                     [@account_id, @amount, @transaction_type, @description])

      case @transaction_type
      in 'c' then db.exec_params(sql_increase_balance, [@account_id, @amount])
      in 'd' then db.exec_params(sql_decrease_balance, [@account_id, @amount])
      end

      account = db.exec_params(sql_select_account, [@account_id]).first

      result.merge!({ 
        limite: account['limit_amount'].to_i,
        saldo: account['balance'].to_i
      })
    end

    result
  end

  def async_call(fibers)
    result = {}

    raise InvalidDataError unless @account_id && @amount && @transaction_type && @description
    raise InvalidDataError if @description && @description.empty?
    raise InvalidDataError unless %w[d c].include?(@transaction_type)

    conn = Database.pool.checkout

    conn.transaction do
      unless conn.is_busy
        conn.send_query_params(sql_select_account, [@account_id])
      end

      fibers << Fiber.current 
      Fiber.yield

      if conn.is_busy && (db_result = conn.get_result)
        account = db_result.to_a.first
        raise NotFoundError unless account

        limit_amount = account['limit_amount'].to_i
        balance = account['balance'].to_i

        raise InvalidLimitAmountError if @transaction_type == 'd' && 
                                          reaching_limit?(balance, limit_amount, @amount)

        unless conn.is_busy
          conn.send_query_params(sql_insert_transaction, [@account_id, @amount, @transaction_type, @description])
        end

        fibers << Fiber.current 
        Fiber.yield

        conn.consume_input
        conn.get_result

        unless conn.is_busy 
          case @transaction_type
          in 'c' then conn.send_query_params(sql_increase_balance, [@account_id, @amount])
          in 'd' then conn.send_query_params(sql_decrease_balance, [@account_id, @amount])
          end
        end

        fibers << Fiber.current 
        Fiber.yield

        conn.consume_input
        conn.get_result

        unless conn.is_busy
          conn.send_query_params(sql_select_account, [@account_id])
        end

        fibers << Fiber.current 
        Fiber.yield

        if conn.is_busy && (db_result = conn.get_result)
          account = db_result.to_a.first

          if account
            result.merge!({ 
              limite: account['limit_amount'].to_i,
              saldo: account['balance'].to_i
            })
          end
        end
      end
    end

    result
  end

  private 

  def sql_increase_balance
    <<~SQL
      UPDATE balances 
      SET amount = amount + $2
      WHERE account_id = $1
    SQL
  end

  def sql_decrease_balance
    <<~SQL
      UPDATE balances 
      SET amount = amount - $2
      WHERE account_id = $1
    SQL
  end

  def sql_insert_transaction
    <<~SQL
      INSERT INTO transactions (account_id, amount, transaction_type, description)
      VALUES ($1, $2, $3, $4)
    SQL
  end

  def sql_select_account
    <<~SQL
      SELECT 
        balances.amount AS balance, 
        accounts.limit_amount AS limit_amount
      FROM accounts 
      JOIN balances ON balances.account_id = accounts.id
      WHERE accounts.id = $1
      FOR UPDATE
    SQL
  end

  def reaching_limit?(balance, limit_amount, amount)
    return false if (balance - amount) > limit_amount
    (balance - amount).abs > limit_amount
  end

  def db = Database.pool.checkout
end
