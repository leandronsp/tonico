require_relative 'bank_statement'
require_relative 'create_transaction'

class Controller < Fiber 
  def initialize(state)
    @state = state

    super(&lambda do |request, params|
      case request
      in 'GET /clientes/:id/extrato'
        fiber = BankStatement.new(@state)
        account, ten_transactions = async_query(fiber, params)

        success({
          "saldo": { 
            "total": account['balance'].to_i,
            "data_extrato": Time.now.strftime("%Y-%m-%d"),
            "limite": account['limit_amount'].to_i
          },
          "ultimas_transacoes": ten_transactions.map do |transaction|
            { 
              "valor": transaction['amount'].to_i,
              "tipo": transaction['transaction_type'],
              "descricao": transaction['description'],
              "realizada_em": transaction['date']
            }
          end
        })
      in 'POST /clientes/:id/transacoes'
        fiber = CreateTransaction.new(@state)
        account = async_query(fiber, params)

        success({
          "limite": account["limit_amount"].to_i,
          "saldo": account["balance"].to_i
        })
      else 
        not_found
      end
    end)
  end

  def async_query(fiber, params)
    continuation, data = fiber.resume(params)

    while continuation == :waiting_pool
      @state[:waiting_pool][Fiber.current] = data
      Fiber.yield

      continuation, data = fiber.resume(params)
    end

    while continuation == :waiting_query
      @state[:waiting_query][Fiber.current] = data
      Fiber.yield

      continuation, data = fiber.resume(params)
    end

    return data if continuation == :result

    fiber.raise rescue nil # terminates preemptively

    return not_found if continuation == :not_found
    return unprocessable_entity if continuation == :invalid
  end

  def success(body) = [:result, [200, body]]
  def not_found = Fiber.yield(:result, [404, {}])
  def unprocessable_entity = Fiber.yield(:result, [422, {}])
end
