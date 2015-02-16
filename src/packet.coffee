require('./buffertools')
sprintf = require('sprintf').sprintf

HEADER_LENGTH = 8

TYPE =
  SQL_BATCH: 0x01
  RPC_REQUEST: 0x03
  TABULAR_RESULT: 0x04
  ATTENTION: 0x06
  BULK_LOAD: 0x07
  TRANSACTION_MANAGER: 0x0E
  LOGIN7: 0x10
  NTLMAUTH_PKT: 0x11
  PRELOGIN: 0x12

typeByValue = {}
for name, value of TYPE
  typeByValue[value] = name

STATUS =
  NORMAL: 0x00,
  EOM: 0x01,                      # End Of Message (last packet).
  IGNORE: 0x02,                   # EOM must also be set.
  RESETCONNECTION: 0x08,
  RESETCONNECTIONSKIPTRAN: 0x10

OFFSET =
  Type: 0,
  Status: 1,
  Length: 2,
  SPID: 4,
  PacketID: 6,
  Window: 7

DEFAULT_SPID = 0;
DEFAULT_PACKETID = 1;
DEFAULT_WINDOW = 0;

NL = '\n'

class Packet
  @fromBuffer: (buffer) ->
    packet = new Packet()
    packet.type = buffer.readUInt8(OFFSET.Type)
    packet.status = buffer.readUInt8(OFFSET.Status)
    packet.spid = buffer.readUInt16BE(OFFSET.SPID)
    packet._packetId = buffer.readUInt8(OFFSET.PacketID)
    packet.window = buffer.readUInt8(OFFSET.Window)
    packet._data = buffer.slice(HEADER_LENGTH)
    packet

  constructor: (typeOrBuffer) ->
    @type = typeOrBuffer
    @status = STATUS.NORMAL
    @spid = DEFAULT_SPID
    @_packetId = DEFAULT_PACKETID
    @window = DEFAULT_WINDOW
    @_data = new Buffer(0)

  length: ->
    @_data.length + HEADER_LENGTH

  resetConnection: (reset) ->
    if reset
      @status |= STATUS.RESETCONNECTION
    else
      @status &= 0xFF - STATUS.RESETCONNECTION

  last: (last) ->
    if arguments.length > 0
      if last
        @status |= STATUS.EOM
      else
        @status &= 0xFF - STATUS.EOM

    @isLast()

  isLast: ->
    !!(@status & STATUS.EOM)

  packetId: (packetId) ->
    if packetId
      @_packetId = packetId % 256
    else
      @_packetId

  addData: (data) ->
    @_data = Buffer.concat([@_data, data])
    @

  data: ->
    @_data

  statusAsString: ->
    statuses = for name, value of STATUS
      if @status & value
        name
    statuses.join(' ').trim()

  headerToString: (indent) ->
    indent ||= ''

    text = sprintf('type:0x%02X(%s), status:0x%02X(%s), length:0x%04X, spid:0x%04X, packetId:0x%02X, window:0x%02X',
      @type, typeByValue[@type],
      @status, @statusAsString(),
      @length(),
      @spid,
      @_packetId,
      @window
    )

    indent + text

  dataToString: (indent) ->
    BYTES_PER_GROUP = 0x04
    CHARS_PER_GROUP = 0x08
    BYTES_PER_LINE = 0x20

    indent ||= ''

    data = @data()
    dataDump = ''
    chars = ''

    for offset in [0..data.length - 1]
      if offset % BYTES_PER_LINE == 0
        dataDump += indent;
        dataDump += sprintf('%04X  ', offset);

      if data[offset] < 0x20 || data[offset] > 0x7E
        chars += '.'

        if ((offset + 1) % CHARS_PER_GROUP == 0) && !((offset + 1) % BYTES_PER_LINE == 0)
          chars += ' '
      else
        chars += String.fromCharCode(data[offset])

      if data[offset]?
        dataDump += sprintf('%02X', data[offset]);

      if ((offset + 1) % BYTES_PER_GROUP == 0) && !((offset + 1) % BYTES_PER_LINE == 0)
        # Inter-group space.
        dataDump += ' '

      if (offset + 1) % BYTES_PER_LINE == 0
        dataDump += '  ' + chars
        chars = ''

        if offset < data.length - 1
          dataDump += NL;

    if chars.length
      dataDump += '  ' + chars

    dataDump

  toString: (indent) ->
    indent ||= ''

    @headerToString(indent) + '\n' + @dataToString(indent + indent)

  payloadString: (indent) ->
    ""

  Object.defineProperty @prototype, "buffer",
    get: ->
      buffer = new Buffer(@length())
      buffer.writeUInt8(@type, OFFSET.Type)
      buffer.writeUInt8(@status, OFFSET.Status)
      buffer.writeUInt16BE(buffer.length, OFFSET.Length)
      buffer.writeUInt16BE(@spid, OFFSET.SPID)
      buffer.writeUInt8(@_packetId, OFFSET.PacketID)
      buffer.writeUInt8(@window, OFFSET.Window)
      @_data.copy(buffer, HEADER_LENGTH)
      buffer

isPacketComplete = (potentialPacketBuffer) ->
  if potentialPacketBuffer.length < HEADER_LENGTH
    false
  else
    potentialPacketBuffer.length >= potentialPacketBuffer.readUInt16BE(OFFSET.Length);

packetLength = (potentialPacketBuffer) ->
  potentialPacketBuffer.readUInt16BE(OFFSET.Length)

exports.Packet = Packet
exports.OFFSET = OFFSET
exports.TYPE = TYPE
exports.isPacketComplete = isPacketComplete
exports.packetLength = packetLength
exports.HEADER_LENGTH = HEADER_LENGTH
