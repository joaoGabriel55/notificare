module ActiveJob
  module Progress
    class ProgressHandle
      def initialize(job_id)
        @job_id = job_id
      end

      def total(n)
        rows = Execution.where(job_id: @job_id).update_all(progress_total: n)
        if rows == 0
          Rails.logger.debug { "[koraci] progress.total called before execution row exists for job_id=#{@job_id}" }
        end
      end

      def advance!(by = 1)
        rows = Execution.where(job_id: @job_id).update_all("progress_current = progress_current + #{by.to_i}")
        if rows == 0
          Rails.logger.debug { "[koraci] progress.advance! called before execution row exists for job_id=#{@job_id}" }
        end
      end
    end
  end
end
