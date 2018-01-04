require "http/client"
require "json"

class NGDPData
  property title : String
  property type : String
  property length : Int32
  property content : Array(String)

  def initialize(@title : String, @type : String, @length : Int32)
    @content = [] of String
  end
end

class NGDP
  property region : String
  getter programCode : String
  getter maxFails : Int32

  def initialize(@region : String, @programCode : String, @maxFails : Int32)
    @port = 1119
  end

  def initialize(@region : String, @programCode : String)
    @port = 1119
    @maxFails = 3
  end

  def request(baseUrl : String, path : String, fails : Int32)
    begin
      client = HTTP::Client.new(URI.parse(baseUrl))
      client.connect_timeout = 300
      client.read_timeout = 300
      response = client.get(path)
      client.close

      response.body
    rescue ex
      puts "NGDP#request: #{ex.message}"
      puts "  Retrying in 30s.."
      fails += 1
      return "" if fails >= @maxFails

      sleep 30
      request(baseUrl, path, fails)
    end
  end

  def request(baseUrl : String, path : String)
    request(baseUrl, path, 0)
  end

  # Contains urls to cdns for this specific program
  #
  # Example output from 2018-01-03
  # Name!STRING:0|Path!STRING:0|Hosts!STRING:0|ConfigPath!STRING:0|Servers!STRING:0
  # eu|tpr/wow|edgecast.blizzard.com blzddist1-a.akamaihd.net level3.blizzard.com|tpr/configs/data|
  # tw|tpr/wow|edgecast.blizzard.com blzddist1-a.akamaihd.net level3.blizzard.com|tpr/configs/data|
  # us|tpr/wow|edgecast.blizzard.com blzddist1-a.akamaihd.net level3.blizzard.com|tpr/configs/data|
  # kr|tpr/wow|blzddistkr1-a.akamaihd.net blizzard.nefficient.co.kr blzddist1-a.akamaihd.net|tpr/configs/data|
  # cn|tpr/wow|client02.pdl.wow.battlenet.com.cn blzddist1-a.akamaihd.net client01.pdl.wow.battlenet.com.cn client04.pdl.wow.battlenet.com.cn|tpr/configs/data|http://client02.pdl.wow.battlenet.com.cn http://blzddist1-a.akamaihd.net http://client01.pdl.wow.battlenet.com.cn http://client04.pdl.wow.battlenet.com.cn https://client02.pdl.wow.battlenet.com.cn/?fallback=1 https://client01.pdl.wow.battlenet.com.cn/?fallback=1 https://client04.pdl.wow.battlenet.com.cn/?fallback=1
  def getCDNs : String
    request("http://#{@region}.patch.battle.net:#{@port}", "/#{@programCode}/cdns")
  end

  # Contains urls to cdns for this specific program
  #
  # Example output from 2018-01-03
  # Region!STRING:0|BuildConfig!HEX:16|CDNConfig!HEX:16|KeyRing!HEX:16|BuildId!DEC:4|VersionsName!String:0|ProductConfig!HEX:16
  # us|0dcd27adeb73b039302160d07f6c3402|3085234dd989d2d1d8fb565becd85ba5||25549|7.3.2.25549|
  # eu|0dcd27adeb73b039302160d07f6c3402|3085234dd989d2d1d8fb565becd85ba5||25549|7.3.2.25549|
  # cn|0dcd27adeb73b039302160d07f6c3402|3085234dd989d2d1d8fb565becd85ba5||25549|7.3.2.25549|
  # kr|0dcd27adeb73b039302160d07f6c3402|3085234dd989d2d1d8fb565becd85ba5||25549|7.3.2.25549|
  # tw|0dcd27adeb73b039302160d07f6c3402|3085234dd989d2d1d8fb565becd85ba5||25549|7.3.2.25549|
  # sg|0dcd27adeb73b039302160d07f6c3402|3085234dd989d2d1d8fb565becd85ba5||25549|7.3.2.25549|
  # xx|0dcd27adeb73b039302160d07f6c3402|3085234dd989d2d1d8fb565becd85ba5||25549|7.3.2.25549|
  def getVersions : String
    request("http://#{@region}.patch.battle.net:#{@port}", "/#{@programCode}/versions")
  end

  # similar to versions, but tailored for use by the Battle.net App background downloader process
  #
  # Example output from 2018-01-03
  # Region!STRING:0|BuildConfig!HEX:16|CDNConfig!HEX:16|KeyRing!HEX:16|BuildId!DEC:4|VersionsName!String:0|ProductConfig!HEX:16
  def getBgdl : String
    request("http://#{@region}.patch.battle.net:#{@port}", "/#{@programCode}/bgdl")
  end

  # contains InstallBlobMD5 and GameBlobMD5
  #
  # Example output from 2018-01-03
  # Region!STRING:0|InstallBlobMD5!HEX:16|GameBlobMD5!HEX:16
  # all|00000000000000000000000000000000|6C70B45A9EC3D9FAB145B71CEAC07D5D
  def getBlobs : String
    request("http://#{@region}.patch.battle.net:#{@port}", "/#{@programCode}/blobs")
  end

  # a blob file that regulates game functionality for the Battle.net App
  def getBlobGame : String
    request("http://#{@region}.patch.battle.net:#{@port}", "/#{@programCode}/blob/game")
  end

  # a blob file that regulates installer functionality for the game in the Battle.net App
  def getBlobInstall : String
    request("http://#{@region}.patch.battle.net:#{@port}", "/#{@programCode}/blob/install")
  end

  # parses data from NGDP contents to JSON for easier accessability
  # TODO: recode: either extend JSON or code own datastructure json a like
  def parse(contents : String)
    if contents == ""
      puts "NGDP#parse: there is no content."
      return JSON.parse("{}")
    end

    contentIO = IO::Memory.new(contents)

    isHeader = true
    data = [] of NGDPData
    contentIO.each_line('\n') do |rowRaw|
      row = IO::Memory.new(rowRaw)
      i = 0
      row.each_line('|') do |column|
        if isHeader
          headData = IO::Memory.new(column.rchop)
          data.push(NGDPData.new(headData.gets('!').to_s.rchop, headData.gets(':').to_s.rchop, headData.gets.to_s.to_i))
        else
          data[i].content.push(column.rchop)
        end
        i += 1
      end
      isHeader = false if isHeader
    end

    json = JSON.build do |json|
      json.object do
        data.each_with_index do |x, i|
          if x.content.size > 1
            json.field(x.title) do
              json.array do
                x.content.each do |c|
                  case x.type.downcase
                  when "string", "hex"
                    json.string(c)
                  when "dec"
                    json.number(c.to_i)
                  else
                    json.string(c)
                  end
                end
              end
            end
          else
            json.field(x.title, x.content[0])
          end
        end
      end
    end

    JSON.parse(json)
  end
end
