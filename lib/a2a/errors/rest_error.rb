# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  # Raised by the REST response middleware when the server returns an
  # HTTP 4xx/5xx with an application/problem+json body. Preserves
  # the HTTP status, title/message, and optional detail array.
  #
  class RestError < Error
    def initialize(message, http_status:, data: nil)
      @wire_data = data
      super(message, code: http_status, http_status: http_status)
    end

    def error_data
      @wire_data
    end
  end
end

__END__
  describe "A2A::RestError" do
    it "has correct http_status and message" do
      err = A2A::RestError.new("Not Found", http_status: 404)
      err.http_status.should == 404
      err.message.should == "Not Found"
    end

    it "uses http_status as the code" do
      err = A2A::RestError.new("Bad Request", http_status: 400)
      err.code.should == 400
    end

    it "preserves wire data" do
      data = [{
        "@type"    => "type.googleapis.com/google.rpc.ErrorInfo",
        "reason"   => "TASK_NOT_FOUND",
        "domain"   => "a2a-protocol.org",
        "metadata" => { "taskId" => "t-1" },
      }]
      err = A2A::RestError.new("Not Found", http_status: 404, data: data)
      err.error_data.should == data
      err.error_data.first["reason"].should == "TASK_NOT_FOUND"
    end

    it "returns nil error_data when no data provided" do
      err = A2A::RestError.new("Internal Server Error", http_status: 500)
      err.error_data.should.be.nil
    end

    it "is a subclass of A2A::Error" do
      err = A2A::RestError.new("fail", http_status: 400)
      err.is_a?(A2A::Error).should == true
    end

    it "serializes to_h with wire data" do
      data = [{ "reason" => "UNSUPPORTED_OPERATION" }]
      err = A2A::RestError.new("Unsupported", http_status: 400, data: data)
      h = err.to_h
      h[:code].should == 400
      h[:http_status].should == 400
      h[:message].should == "Unsupported"
      h[:data].should == data
    end
  end
