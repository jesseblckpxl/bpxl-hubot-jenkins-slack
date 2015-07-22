# Description:
#   Interact with your Jenkins CI server
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_JENKINS_URL
#   HUBOT_JENKINS_AUTH
#   HUBOT_SLACK_API_TOKEN
#
#   Auth should be in the "user:password" format.
#
# Commands:
#
#   hubot jenkins b <jobNumber> - builds the job specified by jobNumber. List jobs to get number.
#   hubot jenkins build <job> - builds the specified Jenkins job
#   hubot jenkins build <job> -p <params> - builds the specified Jenkins job with parameters as key=value&key2=value2
#   hubot jenkins list - lists Jenkins jobs.
#   hubot jenkins describe <job> - Describes the specified Jenkins job
#   hubot jenkins last <job> - Details about the last build for the specified Jenkins job
#   hubot jenkins l <jobNumber> -b <build number> (optional) - uploads Jenkins console log of job specified by jobNumber. List jobs to get number.
#   hubot jenkins log <job> - uploads Jenkins console log of last failed build to chat room
#   hubot jenkins log <job> -b <build number> (optional) -v <build-variant> (optional) - uploads Jenkins console log for specified build variant and number (if provided)
#
# Author:
# Adapted from Doug Cole's jenkins.coffee

querystring = require 'querystring'
fs = require 'fs'
request = require 'request'

# Holds a list of jobs, so we can trigger them with a number
# instead of the job's name. Gets populated on when calling
# list.
jobList = []

jenkinsBuildById = (msg) ->
    # Switch the index with the job name
    job = jobList[parseInt(msg.match[1])]

    if job
      if job.indexOf("build-variant") != -1
        info = job.split("build-variant: [")
        jobname = info[0].split(",")[0]
        variant = info[1].split("]")[0]
        msg.match[1] = jobname
        msg.match[3] = variant
      else
        msg.match[1] = job
      jenkinsBuild(msg)
    else
      msg.reply "I couldn't find that job. Try 'jenkins list' to get a list."

jenkinsBuild = (msg, buildWithEmptyParameters) ->
    job = querystring.escape msg.match[1]
    if jenkinsCheckChannel(msg, job)
      url = process.env.HUBOT_JENKINS_URL
      # Build out the variants and add to build parameters string
      if msg.match[3]
        variants = "BUILD_ALL=false"
        axis = msg.match[3].split(",")
        for v in axis
          bv = v.split("=")
          variants += "&" + bv[0].toUpperCase() + "V=" + bv[1]

      params = if msg.match[2] then msg.match[2] + "&" + variants else variants
      command = if buildWithEmptyParameters then "buildWithParameters" else "build"
      path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/#{command}"

      req = msg.http(path)

      if process.env.HUBOT_JENKINS_AUTH
        auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
        req.headers Authorization: "Basic #{auth}"

      req.header('Content-Length', 0)
      req.post() (err, res, body) ->
          if err
            msg.reply "Jenkins says: #{err}"
          else if 200 <= res.statusCode < 400 # Or, not an error code.
            msg.reply "(#{res.statusCode}) Build started for #{job} #{url}/job/#{job}"
          else if 400 == res.statusCode
            jenkinsBuild(msg, true)
          else
            msg.reply "Jenkins says: Status #{res.statusCode} #{body}"
    else
      msg.reply "I'm sorry, it looks like you're either in the wrong Slack Channel or trying to kick off the wrong Jenkins build. The Jenkins build job must match the channel you are in."

jenkinsDescribe = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    if jenkinsCheckChannel(msg, job)
      path = "#{url}/job/#{job}/api/json"

      req = msg.http(path)

      if process.env.HUBOT_JENKINS_AUTH
        auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
        req.headers Authorization: "Basic #{auth}"

      req.header('Content-Length', 0)
      req.get() (err, res, body) ->
          if err
            msg.send "Jenkins says: #{err}"
          else
            response = ""
            try
              content = JSON.parse(body)
              response += "JOB: #{content.displayName}\n"
              response += "URL: #{content.url}\n"

              if content.description
                response += "DESCRIPTION: #{content.description}\n"

              response += "ENABLED: #{content.buildable}\n"
              response += "STATUS: #{content.color}\n"

              tmpReport = ""
              if content.healthReport.length > 0
                for report in content.healthReport
                  tmpReport += "\n  #{report.description}"
              else
                tmpReport = " unknown"
              response += "HEALTH: #{tmpReport}\n"

              parameters = ""
              for item in content.actions
                if item.parameterDefinitions
                  for param in item.parameterDefinitions
                    tmpDescription = if param.description then " - #{param.description} " else ""
                    tmpDefault = if param.defaultParameterValue then " (default=#{param.defaultParameterValue.value})" else ""
                    parameters += "\n  #{param.name}#{tmpDescription}#{tmpDefault}"

              if parameters != ""
                response += "PARAMETERS: #{parameters}\n"

              msg.send response

              if not content.lastBuild
                return

              path = "#{url}/job/#{job}/#{content.lastBuild.number}/api/json"
              req = msg.http(path)
              if process.env.HUBOT_JENKINS_AUTH
                auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
                req.headers Authorization: "Basic #{auth}"

              req.header('Content-Length', 0)
              req.get() (err, res, body) ->
                  if err
                    msg.send "Jenkins says: #{err}"
                  else
                    response = ""
                    try
                      content = JSON.parse(body)
                      console.log(JSON.stringify(content, null, 4))
                      jobstatus = content.result || 'PENDING'
                      jobdate = new Date(content.timestamp);
                      response += "LAST JOB: #{jobstatus}, #{jobdate}\n"

                      msg.send response
                    catch error
                      msg.send error

            catch error
              msg.send error
    else
      msg.reply "I'm sorry. I don't know the job you want me to describe."

jenkinsLast = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    if jenkinsCheckChannel(msg, job)
      path = "#{url}/job/#{job}/lastBuild/api/json"

      req = msg.http(path)

      if process.env.HUBOT_JENKINS_AUTH
        auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
        req.headers Authorization: "Basic #{auth}"

      req.header('Content-Length', 0)
      req.get() (err, res, body) ->
          if err
            msg.send "Jenkins says: #{err}"
          else
            response = ""
            try
              content = JSON.parse(body)
              response += "NAME: #{content.fullDisplayName}\n"
              response += "URL: #{content.url}\n"

              if content.description
                response += "DESCRIPTION: #{content.description}\n"

              response += "BUILDING: #{content.building}\n"

              msg.send response
    else
      msg.reply "I'm sorry. I don't know the job you entered."

jenkinsList = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    filter = new RegExp(msg.match[2], 'i')
    req = msg.http("#{url}/api/json?depth=1&tree=jobs[name,activeConfigurations[name]]")

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            content = JSON.parse(body)
            for job in content.jobs
              # Add the job to the jobList
              if jobList.indexOf(job.name) == -1
                jobList.push(job.name)
              # Check job against channel name before adding it to the response
              if (jenkinsCheckChannel(msg, job.name))
                index = jobList.indexOf(job.name)
                response += "[#{index}] #{job.name} \n"

              # Check for build variants
              if job.activeConfigurations?
                for variant in job.activeConfigurations
                  job_variant = job.name + ", build-variant: [" + variant.name + "]"
                  # Add build variant to job list
                  if jobList.indexOf(job_variant) == -1
                    jobList.push(job_variant)

                  # Check job against channel before adding it to the response
                  if (jenkinsCheckChannel(msg, job.name))
                    index = jobList.indexOf(job_variant)
                    response += "[#{index}] #{job_variant} \n"

            if response.length == 0
              msg.reply "There appears to be no jobs available for you. If you believe this is an error, please contact the build management team."
            else
              response += "\n Trigger a build by using the commands 'jenkins build <job name> -p <parameters (optional)>' or 'jenkins b [job number]'. To get more information, including build parameters, on a specifc job listed above, use the command 'jenkins describe <job name>'."
              msg.send response

          catch error
            msg.send error

# check that Jenkins job name matches chat room name
jenkinsCheckChannel = (msg, job_name) ->
      channel = msg.envelope.room
      # splitting a string, e.g. android-hongkong, into an array, and getting the last element in that array, e.g. 'hongkong'.
      # Slack channels names should end with market names to correctly match with available Jenkins jobs
      market = channel.split('-').pop()
      return (job_name.indexOf(market) != -1 || channel.match("build-management"))

# Get build log by ID
jenkinsBuildLogById = (msg, robot) ->
    job = jobList[parseInt(msg.match[1]) ]
    build_num = msg.match[2]

    if build_num
      msg.match[2] = build_num

    if job
      if job.indexOf(",") != -1
        name = job.split(", ")
        msg.match[1] = name[0]
        msg.match[3] = name[1]
      else
        msg.match[1] = job
        # Ensure that if a build number was specified it's not mistaken for the build variant in jenkinsBuildLog
        msg.match[3] = null

      jenkinsBuildLog(msg, robot)
    else
      msg.send "I couldn't find that job. Try running 'jenkins list' for a list of available jobs."


jenkinsBuildLog = (msg, robot) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]
    build_num = msg.match[2]
    variant = msg.match[3]

    if (jobList.length == 0)
      msg.send "I couldn't locate any jobs. Please try running 'jenkins list' for a list of available jobs."
    else
      if (!jenkinsCheckChannel(msg, job))
        msg.send "I can't upload build logs for that job. Are you in the correct Slack channel?"
      else
        build = if build_num then "#{build_num}" else "lastBuild"
        path = if variant then "#{url}/job/#{job}/#{variant}/#{build}/consoleText" else "#{url}/job/#{job}/#{build}/consoleText"

        channel = ""
        log_file = "log-#{job}-#{build}.txt"
        req = msg.http(path)

        if process.env.HUBOT_JENKINS_AUTH
          auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
          req.headers Authorization: "Basic #{auth}"

        req.get() (err,res,body) ->
          if err
            msg.send "Whoops, something went wrong! #{err}"
          else if 400 <= res.statusCode
            msg.send "#{res.statusCode}: Build log not found, try passing in a different build number after the job name? "
          else
            try
              fs.writeFile log_file, "#{body}", (error) ->
                if error
                  console.error("Error writing file #{log_file}", error)
                else
                  log_body = ->
                    fs.readFile log_file, 'utf8', (error, body)->
                      console.log("something went wrong trying when trying to read in the log file") if error
                    return body

                  # get the slack channel id to pass to slack api upload file method
                  for k of robot.channels
                    channel_name = "#{robot.channels[k].name}"
                    if channel_name.match msg.envelope.room
                      console.log("#{k} :#{robot.channels[k].name}")
                      channel += "#{k}"
                  #check private groups if channel_name still empty
                  if channel_name.match ""
                    for j of robot.groups
                      group_name = "#{robot.groups[j].name}"
                      if group_name.match msg.envelope.room
                        console.log("#{j}: #{robot.groups[j].name}")
                        channel += "#{j}"
                  api_token = process.env.HUBOT_SLACK_API_TOKEN
                  options = {token: "#{api_token}", channels: "#{channel}", filename: "#{job}-build-#{build}-log.txt"}
                  options["content"] = log_body()

                  request.post "https://api.slack.com/api/files.upload", {form: options }, (error, response, body) ->
                    if error
                      msg.send "something went wrong: #{error}"
                    else
                      msg.send "Build file uploaded."
                      # Delete build log file after upload
                      fs.unlinkSync log_file

            catch error
              msg.send error

module.exports = (robot) ->
  robot.respond /j(?:enkins)? build ([\w\.\-_]+)?(?:[ \-p]+)?([\w\.\-_=&,\w=]+)?/i, (msg) ->
    jenkinsBuild(msg, false)

  robot.respond /j(?:enkins)? b (\d+)/i, (msg) ->
    jenkinsBuildById(msg)

  robot.respond /j(?:enkins)? list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /j(?:enkins)? describe (.*)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.respond /j(?:enkins)? last (.*)/i, (msg) ->
    jenkinsLast(msg)

  robot.respond /j(?:enkins)? log ([\w\.\-_]+)(?:[\-b\ ]+)?([\d]+)?(?:[ \-v \ ]+)?([\w\.\-_=,\w=]+)?/i, (msg) ->
    slack_bot = robot.adapter.client
    jenkinsBuildLog(msg, slack_bot)

  robot.respond /j(?:enkins)? l (\d+)(?:[\,\-b ]+)?(\d+)?/i, (msg) ->
    slack_bot = robot.adapter.client
    jenkinsBuildLogById(msg, slack_bot)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild
    describe: jenkinsDescribe
    last: jenkinsLast
    log: jenkinsBuildLog
  }
