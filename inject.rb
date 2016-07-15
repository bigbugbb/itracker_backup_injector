#!/usr/bin/env ruby

require 'date'
require 'pg'
require 'logger'
require 'aws-sdk'

@logger = Logger.new(STDOUT)
PREFIX_PATTERN = '%Y/%m/%d'
BUCKET_NAME = 'itracker-track-data'

# Instantiate a new client for Amazon Simple Storage Service (S3). With no
# parameters or configuration, the AWS SDK for Ruby will look for access keys
# and region in these environment variables:
#
#    AWS_ACCESS_KEY_ID='...'
#    AWS_SECRET_ACCESS_KEY='...'
#    AWS_REGION='...'
#
# For more information about this interface to Amazon S3, see:
# http://docs.aws.amazon.com/sdkforruby/api/Aws/S3/Resource.html

s3 = Aws::S3::Client.new(
  region: ENV['aws_region'],
  access_key_id: ENV['access_key_id'],
  secret_access_key: ENV['secret_access_key']
)

def with_psql
  begin
    psql_config = {
      :dbname   => ENV['itracker_psql_database'],
      :user     => ENV['itracker_psql_user'],
      :password => ENV['itracker_psql_password'],
      :host     => ENV['itracker_psql_host'],
      :port     => ENV['itracker_psql_port']
    }
    psql = PG.connect psql_config
    yield psql
  ensure
    psql.close if psql
  end
end

def fetch_objects(client, bucket, prefix)
  marker, done = nil, false
  while !done do
    resp = client.list_objects(bucket: bucket, prefix: prefix, marker: marker)

    yield resp.contents

    if resp.is_truncated
      marker = resp.contents[-1].key
    else
      done = true
    end
  end
end

def import_objects(psql, objects)
  begin
    values = nil
    objects.each do |object|
      s3_key   = object.key
      category = object.key.split('/').last[0..-9]
      date     = object.key[0, 10].gsub!('/', '-')
      hour     = object.key[11, 2].to_i
      now      = DateTime.now.to_s
      # object_import_sql = """
      #   INSERT INTO backups (s3_key, category, date, hour, created_at, updated_at)
      #           SELECT '#{s3_key}', '#{category}', '#{date}', #{hour}, '#{now}', '#{now}'
      #           WHERE NOT EXISTS (SELECT 1 FROM backups WHERE s3_key='#{s3_key}')
      # """
      if !values
        values = "('#{s3_key}', '#{category}', '#{date}', #{hour}, '#{now}', '#{now}')"
      else
        values += ",('#{s3_key}', '#{category}', '#{date}', #{hour}, '#{now}', '#{now}')"
      end
    end

    if values
      sql = """
        INSERT INTO backups (s3_key, category, date, hour, created_at, updated_at)
        VALUES #{values}
        ON CONFLICT DO NOTHING
      """
      @logger.info(sql)
      psql.exec sql
    end
  rescue PG::Error => e
    @logger.error(e.message)
  end
end

with_psql do |psql|
  (0..60).each do |n|
    date = (Date.today - n).strftime(PREFIX_PATTERN)
    fetch_objects(s3, BUCKET_NAME, date) do |objects|
      import_objects(psql, objects)
    end
  end
end
