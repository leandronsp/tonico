require_relative 'responder'

class Controller < Fiber 
  class NotFoundError < StandardError; end
  class InvalidDataError < StandardError; end

  def self.call(*args)
    instance = new do |state, client, request, params|
      case request
      in 'GET /clientes/:id/extrato'
        sql_account = <<~SQL
          SELECT 
            limit_amount,
            balance
          FROM accounts
          WHERE id = $1
        SQL

        sql_ten_transactions = <<~SQL
          SELECT 
                  amount, 
                  transaction_type, 
                  description, 
                  TO_CHAR(date, 'YYYY-MM-DD HH:MI:SS.US') AS date
          FROM transactions
          WHERE transactions.account_id = $1
          ORDER BY date DESC
          LIMIT 10
        SQL

        while state[:pool].available == 0
          state[:waiting_pool][Fiber.current] = state[:pool]
          Fiber.yield
        end

        state[:pool].with do |conn|
          poll_status = conn.connect_poll

          until poll_status == PG::PGRES_POLLING_OK || poll_status == PG::PGRES_POLLING_FAILED
            case poll_status
            in PG::PGRES_POLLING_READING
              IO.select([conn.socket_io], nil, nil)
            in PG::PGRES_POLLING_WRITING
              IO.select(nil, [conn.socket_io], nil)
            end

            poll_status = conn.connect_poll
          end

          conn.send_query_params(sql_account, [params['id']])

          state[:waiting_query][Fiber.current] = conn
          Fiber.yield

          result = conn.get_result
          conn.discard_results

          account = result.to_a.first
          raise NotFoundError unless account

          conn.send_query_params(sql_ten_transactions, [params['id']])

          state[:waiting_query][Fiber.current] = conn
          Fiber.yield

          result = conn.get_result
          conn.discard_results

          ten_transactions = result.to_a

          body = {
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
          }

          Responder.call(client, 200, body)
        end
      in 'POST /clientes/:id/transacoes'
        reached_limit = lambda do |balance, amount, limit_amount|
          return false if (balance - amount) > limit_amount
          (balance - amount).abs > limit_amount
        end

        raise InvalidDataError unless params['id'] && params['valor'] && params['tipo'] && params['descricao'] 
        raise InvalidDataError if params['descricao'] && params['descricao'].empty?
        raise InvalidDataError if params['descricao'] && params['descricao'].size > 10
        raise InvalidDataError if params['valor'] && (!params['valor'].is_a?(Integer) || !params['valor'].positive?)
        raise InvalidDataError unless %w[d c].include?(params['tipo'])

        operator = params['tipo'] == 'd' ? '-' : '+'

        sql_insert_transaction = <<~SQL
          INSERT INTO transactions (account_id, amount, transaction_type, description)
          VALUES ($1, $2, $3, $4)
        SQL

        sql_update_balance = <<~SQL
          UPDATE accounts 
          SET balance = balance #{operator} $2
          WHERE id = $1
        SQL

        sql_account = <<~SQL
          SELECT 
            limit_amount,
            balance
          FROM accounts
          WHERE id = $1
          FOR UPDATE
        SQL

        while state[:pool].available == 0
          state[:waiting_pool][Fiber.current] = state[:pool]
          Fiber.yield
        end

        state[:pool].with do |conn|
          poll_status = conn.connect_poll

          until poll_status == PG::PGRES_POLLING_OK || poll_status == PG::PGRES_POLLING_FAILED
            case poll_status
            in PG::PGRES_POLLING_READING
              IO.select([conn.socket_io], nil, nil)
            in PG::PGRES_POLLING_WRITING
              IO.select(nil, [conn.socket_io], nil)
            end

            poll_status = conn.connect_poll
          end

          conn.transaction do
            conn.send_query_params(sql_account, [params['id']])

            state[:waiting_query][Fiber.current] = conn
            Fiber.yield

            result = conn.get_result
            conn.discard_results

            account = result.to_a.first
            raise NotFoundError unless account

            raise InvalidDataError if params['tipo'] == 'd' && 
              reached_limit.call(account['balance'].to_i, params['valor'].to_i, account['limit_amount'].to_i)

            conn.send_query_params(sql_insert_transaction, params.values_at('id', 'valor', 'tipo', 'descricao'))

            state[:waiting_query][Fiber.current] = conn
            Fiber.yield

            _result = conn.get_result
            conn.discard_results

            conn.send_query_params(sql_update_balance, params.values_at('id', 'valor'))

            state[:waiting_query][Fiber.current] = conn
            Fiber.yield

            _result = conn.get_result
            conn.discard_results

            conn.send_query_params(sql_account, [params['id']])

            state[:waiting_query][Fiber.current] = conn
            Fiber.yield

            result = conn.get_result
            conn.discard_results

            account = result.to_a.first

            body = {
              "limite": account["limit_amount"].to_i,
              "saldo": account["balance"].to_i
            }

            Responder.call(client, 200, body)
          end
        end
      else 
        raise NotFoundError
      end
    rescue InvalidDataError
      Responder.call(client, 422, {})
    rescue NotFoundError
      Responder.call(client, 404, {})
    end

    while instance.alive?
      instance.resume(*args)
    end
  end
end
