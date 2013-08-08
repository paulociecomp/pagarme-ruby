# encoding: utf-8
require 'openssl'
require 'base64'
require File.join(File.dirname(__FILE__), '..', 'pagarme')

module PagarMe
  class Transaction < Model
	attr_reader :date_created, :id, :status
	attr_accessor :amount, :card_number, :card_holder_name, :card_expiracy_month, :card_expiracy_year, :card_cvv, :card_hash, :installments, :card_last_digits, :postback_url, :payment_method
	@root_url = '/transactions'

	# initializers

	def initialize(first_parameter = nil, server_response = nil)
	  @date_created = nil
	  @id = nil
	  @status = 'local'
	  self.installments = 1

	  self.card_number = self.card_holder_name = self.card_expiracy_month = self.card_expiracy_year = self.card_cvv = ""
	  self.amount = 0
	  self.postback_url = nil
	  self.payment_method = 'credit_card'

	  # First parameter can be a hash with transaction parameters
	  # or a encrypted card_hash that came from client.
	  if first_parameter.class == String
		self.card_hash = first_parameter
	  elsif first_parameter.class == Hash
		self.amount = first_parameter[:amount] || ''
		self.card_number = first_parameter[:card_number] || ''
		self.card_holder_name = first_parameter[:card_holder_name] || ''
		self.card_expiracy_month = first_parameter[:card_expiracy_month] || ''
		self.card_expiracy_year = first_parameter[:card_expiracy_year] || ''
		self.card_cvv = first_parameter[:card_cvv] || ''
		self.installments = first_parameter[:installments] if first_parameter[:installments]
		self.postback_url = first_parameter[:postback_url]
		self.payment_method = first_parameter[:payment_method] || 'credit_card'
	  end

	  update_fields_from_response(server_response) if server_response
	end

	# server requests methods

	def charge
	  validation_error = self.card_hash ? nil : error_in_transaction
	  raise RequestError.new(validation_error) if validation_error
	  raise RequestError.new("Transaction already charged!") if @status != 'local'

	  request = PagarMe::Request.new('/transactions', 'POST')
	  request.parameters = {
		:amount => self.amount.to_s,
		:payment_method => self.payment_method,
		:installments => self.installments.to_i,
		:card_hash => self.payment_method == 'credit_card' ? (self.card_hash ? self.card_hash : generate_card_hash) : nil,
		:postback_url => self.postback_url
	  }

	  response = request.run
	  update_fields_from_response(response)
	end

	def chargeback
	  raise RequestError.new("Transaction already chargebacked!") if @status == 'chargebacked'
	  raise RequestError.new("Transaction needs to be paid to be chargebacked") if @status != 'paid'
	  raise RequestError.new("Boletos não podem ser cancelados") if self.payment_method != 'credit_card'

	  request = PagarMe::Request.new("/transactions/#{self.id}", 'DELETE')
	  response = request.run
	  update_fields_from_response(response)
	end


	private

	def update_fields_from_response(response)
	  @status = response['status']
	  @date_created = response['date_created']
	  self.amount = response['amount']
	  self.card_holder_name = response['costumer_name']
	  self.installments = (!response['installments'] ? 1 : response['installments'].to_i)
	  self.card_last_digits = response['card_last_digits']
	  self.payment_method = response['payment_method']
	  @id = response['id']
	end

	def is_valid_credit_card(card)
	  s1 = s2 = 0
	  card.to_s.reverse.chars.each_slice(2) do |odd, even| 
		s1 += odd.to_i

		double = even.to_i * 2
		double -= 9 if double >= 10
		s2 += double
	  end
	  (s1 + s2) % 10 == 0
	end

	def error_in_transaction
	  if self.amount.to_i <= 0
		"Valor inválido."
	  end

	  if self.payment_method == 'credit_card'
		if self.card_number.length < 16 || self.card_number.length > 20 || !is_valid_credit_card(self.card_number)
		  "Número do cartão inválido."
		elsif self.card_holder_name.length == 0
		  "Nome do portador inválido."
		elsif self.card_expiracy_month.to_i <= 0 || self.card_expiracy_month.to_i > 12
		  "Mês de expiração inválido."
		elsif self.card_expiracy_year.to_i <= 0
		  "Ano de expiração inválido."
		elsif self.card_cvv.length < 3 || self.card_cvv.length > 4
		  "Código de segurança inválido."
		else
		  nil
		end
	  end
	end

	def card_data_parameters
	  {
		:card_number => self.card_number,
		:card_holder_name => self.card_holder_name,
		:card_expiracy_date => "#{self.card_expiracy_month}#{self.card_expiracy_year}",
		:card_cvv => self.card_cvv
	  }
	end

	def generate_card_hash
	  request = PagarMe::Request.new("/transactions/card_hash_key", 'GET')
	  response = request.run

	  public_key = OpenSSL::PKey::RSA.new(response['public_key'])
	  "#{response['id']}_#{Base64.strict_encode64(public_key.public_encrypt(card_data_parameters.to_params))}"
	end
  end
end
