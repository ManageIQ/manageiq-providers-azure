# Required in order to include timestamp information on requests for RestClient.

$azure_log.define_singleton_method(:<<, lambda{ |msg| log(level, msg.strip) })
