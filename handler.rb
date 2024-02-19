# frozen_string_literal: true

require 'pg'
require 'json'

require_relative 'request'
require_relative 'bank_statement'
require_relative 'transaction'

class Handler
  VALIDATION_ERRORS = [
    PG::InvalidTextRepresentation,
    PG::StringDataRightTruncation,
    Transaction::InvalidDataError,
    Transaction::InvalidLimitAmountError
  ].freeze

  def self.call(client, fibers = [])
    request, params = Request.parse(client)

    begin
      case request
      in "GET /clientes/:id/extrato"
        if ENV['ASYNC']
          body = BankStatement.new(params['id']).async_call(fibers).to_json
        else 
          body = BankStatement.new(params['id']).call.to_json
        end

        status = 200
      in "POST /clientes/:id/transacoes"
        if ENV['ASYNC']
          body = Transaction.new(
            params['id'], 
            params['valor'], 
            params['tipo'], 
            params['descricao']
          ).async_call(fibers).to_json
        else 
          body = Transaction.new(
            params['id'], 
            params['valor'], 
            params['tipo'], 
            params['descricao']
          ).call.to_json
        end

        status = 200
      else 
        status = 404
      end
    rescue PG::ForeignKeyViolation, 
           BankStatement::NotFoundError, 
           Transaction::NotFoundError
      status = 404
    rescue *VALIDATION_ERRORS => err
      status = 422
      body = { error: err.message }.to_json
    end

    response = <<~HTTP
      HTTP/2.0 #{status}
      Content-Type: application/json

      #{body}
    HTTP

    client.puts(response)
    client.close
  end
end
