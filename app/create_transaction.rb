# Returns: 
#   - waiting_pool
#   - waiting_query
#   - not_found
#   - invalid
#   - result
class CreateTransaction < Fiber 
  def initialize(state)
    @state = state
    @pool = @state[:pool]

    super(&lambda do |params|
      if @pool.available == 0
        Fiber.yield(:waiting_pool, @pool)
      end

      @pool.with do |conn|
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
          conn.send_query_params(sql_account_locking, [params['id']])
          Fiber.yield(:waiting_query, conn)

          result = conn.get_result
          conn.discard_results

          account = result.to_a.first

          Fiber.yield(:not_found, nil) unless account
          Fiber.yield(:invalid, nil) if !valid?(params) || reached_limit?(params, account)

          conn.send_query_params(sql_insert_transaction, params.values_at('id', 'valor', 'tipo', 'descricao'))
          Fiber.yield(:waiting_query, conn)

          _result = conn.get_result
          conn.discard_results
          
          operator = debit?(params) ? '-' : '+'
          conn.send_query_params(sql_update_balance(operator), params.values_at('id', 'valor'))
          Fiber.yield(:waiting_query, conn)

          _result = conn.get_result
          conn.discard_results

          conn.send_query_params(sql_account_locking, [params['id']])
          Fiber.yield(:waiting_query, conn)

          result = conn.get_result
          conn.discard_results

          account = result.to_a.first

          [:result, account]
        end
      end
    end)
  end

  def valid?(params)
    return false unless params['id'] && params['valor'] &&
                                        params['tipo'] && params['descricao'] 

    return false if params['descricao']&.empty?
    return false if params['descricao'] && params['descricao'].size > 10

    return false if params['valor'] && (!params['valor'].is_a?(Integer) || 
                                        !params['valor'].positive?)

    return false unless %w[d c].include?(params['tipo'])

    true
  end

  def debit?(params)
    params['tipo'] == 'd'
  end

  def reached_limit?(params, account)
    amount = params['valor'].to_i
    balance = account['balance'].to_i
    limit_amount = account['limit_amount'].to_i

    return false unless debit?(params)
    return false if (balance - amount) > limit_amount

    (balance - amount).abs > limit_amount
  end

  def sql_insert_transaction
    <<~SQL
      INSERT INTO transactions (account_id, amount, transaction_type, description)
      VALUES ($1, $2, $3, $4)
    SQL
  end 
  
  def sql_update_balance(operator)
    <<~SQL
      UPDATE accounts 
      SET balance = balance #{operator} $2
      WHERE id = $1
    SQL
  end 

  def sql_account_locking
    <<~SQL
      SELECT 
        limit_amount,
        balance
      FROM accounts
      WHERE id = $1
      FOR UPDATE
    SQL
  end
end
