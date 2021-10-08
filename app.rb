require 'sinatra'
require 'google/cloud/storage'
require 'digest'
require 'json'

storage = Google::Cloud::Storage.new(project_id: 'cs291a')
bucket = storage.bucket 'cs291project2', skip_lookup: true

def isValidDigest(string)
  return !string.match(/\A[a-f0-9]{64}\z/).nil?
end

def isSHA256Format(string)
  path = string.split('/')
  if path.length != 3
    return false
  end
  if path[0].length != 2 || path[1].length != 2 || path[2].length != 60
    return false
  end

  path = path.join()
  return isValidDigest(path)
end

def convertToSHA256Format(string)
  path = string.split('/')
  return path.join()
end

def convertToGCSFormat(string)
  return string[0..1] + '/' + string[2..3] + '/' + string[4..-1]
end

get '/' do
  redirect '/files/', 302
end

get '/files/' do
  all_files = bucket.files
  file_names = []
  all_files.all do |file|
    puts "found this file: #{file.name}"
    if isSHA256Format(file.name)
      hexdigest = convertToSHA256Format(file.name)
      file_names.append(hexdigest)
    end
  end
  file_names.sort
  content_type 'application/json'
  file_names_json = file_names.to_json
  body file_names_json
end

post '/files/' do
  if params.keys.include?('file')
    file = params['file']['tempfile']
    if file.nil? || file == 'tempfile' || file.size > 1048576
      status 422
    else
      sha256 = Digest::SHA256.file file
      hexdigest = sha256.hexdigest
      object_name = convertToGCSFormat(hexdigest)
      gcs_file = bucket.file object_name
      if gcs_file.nil? #does not exist
        bucket.create_file file, object_name, content_type: params['file']['type']
        status 201
        content_type 'application/json'
        body_json = { "uploaded" => hexdigest }.to_json
        body body_json
      else #already exists
        status 409
      end
    end
  else
    status 422
  end
end

get '/files/:digest' do |digest|
  digest = digest.downcase
  if isValidDigest(digest)
    gcs_file = bucket.file convertToGCSFormat(digest)
    if gcs_file.nil? # does not exist
      status 404
    else
      downloaded = gcs_file.download
      downloaded.rewind
      contents = downloaded.read
      content_type gcs_file.content_type # doesn't work for now
      body contents
    end
  else
    status 422
  end
end

delete '/files/:digest' do |digest|
  digest = digest.downcase
  if isValidDigest(digest)
    gcs_file = bucket.file convertToGCSFormat(digest)
    if !gcs_file.nil? #does exist
      gcs_file.delete
    end
    status 200
  else
    status 422
  end
end
