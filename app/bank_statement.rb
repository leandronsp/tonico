# Returns: 
#   - waiting_pool
#   - waiting_query
#   - not_found
#   - result
class BankStatement < Fiber 
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

        conn.send_query_params(sql_account, [params['id']])
        Fiber.yield(:waiting_query, conn)

        result = conn.get_result
        conn.discard_results

        account = result.to_a.first
        Fiber.yield(:not_found, nil) unless account

        conn.send_query_params(sql_ten_transactions, [params['id']])
        Fiber.yield(:waiting_query, conn)

        result = conn.get_result
        conn.discard_results

        ten_transactions = result.to_a

        [:result, [account, ten_transactions]]
      end
    end)
  end

  def sql_account
    <<~SQL
      SELECT 
        limit_amount,
        balance
      FROM accounts
      WHERE id = $1
    SQL
  end

  def sql_ten_transactions
    <<~SQL
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
  end
end
