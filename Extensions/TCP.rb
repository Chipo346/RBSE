require 'rubygems'
require 'socket'
require 'to_bool'

class TCP

	attr_accessor :clients, :server

	def initialize(main_class)
		@parent = main_class
		@clients = Array.new
		@server
	end
	
	def connectServer
		@server = TCPServer.open(@parent.server_config['server_port'])
		if @server != nil
			@parent.logger.info('Successfully connected to the Game server')
		else
			@parent.logger.info('Failed to connect to the Game server')
		end
	end
	
	def listenServer
		Thread.new(@server.accept) do |connection|
			@parent.logger.info("Accepting connection from #{connection.peeraddr[2]}")
			client = CPUser.new(@parent, connection)
			@clients << client
			begin
				while (data = connection.gets("\0"))
				if data != nil
					data = data.chomp
				end
				self.handleIncomingData(data, client)	
			end
			rescue Exception => err
				@parent.logger.error("#{err} (#{err.class}) - #{err.backtrace.join("\n\t")}")
				raise
				ensure 
					if @parent.game_sys.iglooMap.has_key?(client.ID)
						@parent.game_sys.iglooMap.delete(client.ID)
					end
					client.handleBuddyOffline
					client.removePlayerFromRoom
					@parent.game_sys.handleLeaveTable([], client)
					self.handleRemoveClient(connection)
			end
        end
	end
	
	def handleIncomingData(data, client)
		@parent.logger.debug('Incoming data: ' + data.to_s)
		packet_type = data[0,1]
		case packet_type
			when '<'
				self.handleXMLData(data, client)
			when '%'
				self.handleXTData(data, client)
			else
				self.handleRemoveClient(client.sock)
		end
	end
	
	def handleXMLData(data, client)
		if data.include?('policy-file-request')
			return @parent.login_sys.handleCrossDomainPolicy(client)
		end
		hash_data = @parent.parseXML(data)
		if hash_data == false
			return self.handleRemoveClient(client.sock)
		end
		if @parent.login_sys.xml_handlers.has_key?('policy-file-request')
			return @parent.login_sys.handleCrossDomainPolicy(client)
		end
		if hash_data['msg']['t'] == 'sys'
			action = hash_data['msg']['body']['action']
			if @parent.login_sys.xml_handlers.has_key?(action)
				handler = @parent.login_sys.xml_handlers[action]
				@parent.hooks.each do |hook, hookClass|
					if @parent.hooks[hook].dependencies['hook_type'] == 'login'
						if @parent.hooks[hook].respond_to?(handler) == true && @parent.hooks[hook].callBefore == true && @parent.hooks[hook].callAfter == false
							hookClass.send(handler, hash_data, client)
						end
					end
				end
				if @parent.login_sys.respond_to?(handler) == true
					@parent.login_sys.send(handler, hash_data, client)
				end
				@parent.hooks.each do |hook, hookClass|
					if @parent.hooks[hook].dependencies['hook_type'] == 'login'
						if @parent.hooks[hook].respond_to?(handler) == true && @parent.hooks[hook].callAfter == true && @parent.hooks[hook].callBefore == false
							hookClass.send(handler, hash_data, client)
						end
					end
				end
			end
		end
	end
	
	def handleXTData(data, client)
		@parent.game_sys.handleData(data, client)
	end
	
	def getClientBySock(socket)
		@clients.each_with_index do |client, key|
			if @clients[key].sock == socket
				return @clients[key]
			end
		end
	end
	
	def handleRemoveClient(socket)
		@clients.each_with_index do |client, key|
			if @clients[key].sock == socket
				@clients[key].sock.close
				@clients.delete(client)
				@parent.logger.info('A client disconnected from the server')
			end
		end
	end
	
end
