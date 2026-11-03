# frozen_string_literal: true

# Some code replaces Rails.logger with a plain ::Logger, which has no #silence.
# Rails calls logger.silence for the health check (/up, used by the deploy) and in
# other places, so give every Logger that ability. Safe if it already has it.
require "active_support/logger_silence"

::Logger.include(ActiveSupport::LoggerSilence) unless ::Logger.method_defined?(:silence)
