require_relative 'database'

class BankStatement
  class NotFoundError < StandardError; end

  def self.call(*args)
    new(*args).call
  end

  def initialize(account_id)
    @account_id = account_id
  end

  def call
    result = {}

    Database.pool.with do |conn|
      conn.transaction do 
        account = conn.exec_params(sql_select_account, [@account_id]).first
        raise NotFoundError unless account

        result["saldo"] = {  
          "total": account['balance'].to_i,
          "data_extrato": Time.now.strftime("%Y-%m-%d"),
          "limite": account['limit_amount'].to_i
        }

        ten_transactions = conn.exec_params(sql_ten_transactions, [@account_id])

        result["ultimas_transacoes"] = ten_transactions.map do |transaction|
          { 
            "valor": transaction['amount'].to_i,
            "tipo": transaction['transaction_type'],
            "descricao": transaction['description'],
            "realizada_em": transaction['date']
          }
        end
      end

      result
    end
  end

  private 

  def sql_ten_transactions
    <<~SQL
      SELECT amount, transaction_type, description, TO_CHAR(date, 'YYYY-MM-DD HH:MI:SS.US')
      FROM transactions
      WHERE transactions.account_id = $1
      ORDER BY date DESC
      LIMIT 10
    SQL
  end

  def sql_select_account
    <<~SQL
      SELECT balance, limit_amount
      FROM accounts 
      WHERE id = $1
    SQL
  end
end
