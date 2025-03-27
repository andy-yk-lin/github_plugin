BASEDIR=$(dirname "$0")
#Check Variables
if [ "$product" == "" ]; then
  echo empty productName
  exit 1
else
  #Encode Product Name
  echo productname ${product}
  productName=$(echo -ne ${product} | base64 | sed 's/=//g')
  echo encode productname ${productName}
  if [ "$productName" = "product" ]; then
  echo encode productName Fail
  exit 2
  else
    if [ "$project" == "" ]; then
      echo empty projectName
      exit 3
    else
      #Encode Project Name
      echo projectname ${project}
      projectName=$(echo -ne ${project} | base64 | sed 's/=//g')
      echo encode projectname ${projectName}
        if [ "$projectName" = "project" ]; then
        echo encode projectName Fail
        exit 4
        else
          if [ "$userKey" == "" ]; then
            echo empty userKey
            exit 5
          else
            echo userkey $userKey
            if [ "$orgToken" == "" ]; then
              echo empty orgToken
              exit 6
            else
              #API Create WhiteSource Product & Get Product Token
              echo orgtoken ${orgToken}
              data={"userKey":"$userKey","orgToken":"$orgToken","requestType":"createProduct","productName":"$productName"}
              curl --header ${header} --data ${data} ${api}
              echo API Create Product
              echo curl --header ${header} --data ${data} ${api} 
              data={"userKey":"$userKey","orgToken":"$orgToken","requestType":"getAllProducts"}
              pattern="\"productName\":\"$productName\",\"productToken\":\"[0-9a-f]*\""
              productToken=$(curl --header ${header} --data ${data} ${api} | grep -oEi ${pattern} | cut -d ':' -f 3 | cut -d '"' -f 2)
              if [ "$productToken" == "" ]; then
                echo empty productToken
                exit 7
              else
                #API Create WhiteSource Project & Get Project Token
                echo API Get ProductToken
                echo productToken ${productToken}
                data={"userKey":"$userKey","orgToken":"$orgToken","requestType":"createProject","productToken":"$productToken","projectName":"$projectName"}
                echo API Create Project
                curl --header ${header} --data ${data} ${api}
                data={"userKey":"$userKey","productToken":"$productToken","requestType":"getAllProjects"}
                curl --header ${header} --data ${data} ${api}
                pattern="\"projectName\":\"$projectName\",\"projectToken\":\"[0-9a-f]*\""
                projectToken=$(curl --header ${header} --data ${data} ${api} | grep -oEi ${pattern} | cut -d ':' -f 3 | cut -d '"' -f 2)
                echo API Get ProjectToken
                echo curl --header ${header} --data ${data} ${api}
                if [ "$projectToken" == "" ]; then
                  echo empty projectToken
                  exit 8
                else
                  #Start WhiteSource Unified Agent Scan
                  echo ProjectToken ${projectToken}
                  echo Start Unified Agent Scan
                  java -jar $BASEDIR/wss-unified-agent.jar -c $BASEDIR/scan-wss-unified-agent.config -apiKey ${orgToken} -userKey ${userKey} -productToken ${productToken} -projectToken ${projectToken}  -d ${WORKSPACE}
                  #Upload Scan Result
                  echo Start Upload Result
                  java -jar $BASEDIR/wss-unified-agent.jar -c $BASEDIR/upload-wss-unified-agent.config -apiKey ${orgToken} -userKey ${userKey} -productToken ${productToken} -projectToken ${projectToken} -requestFiles ./EraseResult.txt > summary.txt
                  #API Get Support Token To Check Upload States
                  pattern="Support\sToken:\s[0-9a-f]*"
                  cat summary.txt | grep -oEi $pattern | cut -d ' ' -f 3 > token.txt
                  supportToken=$(sed '1,2d' 'token.txt')
                  echo Get Support Token To Check Upload State
                  echo SupportToken ${supportToken}
                  if [ "$supportToken" == "" ]; then
                    echo empty supportToken
                    exit 9
                  else
                    data={"userKey":"$userKey","orgToken":"$orgToken","requestType":"getRequestState","requestToken":"$supportToken"}
                    pattern="\"requestState\":\"[A-Z_]*\""
                    STATE=$(curl --header ${header} --data $data $api | grep -oEi $pattern | cut -d ':' -f 2 | cut -d '"' -f 2 )
                    echo API To Check Upload State
                    echo State: ${STATE}
                    while [ "$STATE" != "FINISHED" ]; do
                      sleep 10
                      echo State: ${STATE}
                      STATE=$(curl --header ${header} --data $data $api | grep -oEi $pattern | cut -d ':' -f 2 | cut -d '"' -f 2 )
                      case "$STATE" in
                        UNKNOWN)
                          #State = unknow -> either orgToken or requestToken are invalid
                          echo "Unknown error"
                          break
                          ;;
                        IN_PROGRESS)
                          #State = IN_PROGRESS -> update is in progress
                          echo "Still in progress"
                          ;;
                        UPDATED)
                          #State = UPDATED ->  inventory has been modified yet alerts have not been calculated yet
                          echo "Updating"
                          ;;
                        FINISHED)
                          #State = FINISHED -> alerts have been calculated successfully
                          #API Get Project Risk Report
                          echo "Finished"
                          break
                          ;;
                        FAILED)
                          #State = FAILED -> an error has occurred during the update process
                          echo "Failed"
                          break
                          ;;
                      esac
                      done
                      echo Update State:$STATE
                      echo "Get Project Risk Report"
                      data={"userKey":"$userKey","orgToken":"$orgToken","requestType":"getProjectRiskReport","projectToken":"$projectToken"}
                      curl --header ${header} --data ${data} ${api} -o ./whitesource/projectRisk#$BUILD_NUMBER.pdf
                      #API Get Policy Violation Alert Report To Analysis Project Policy Violation Type And Quantity
                      echo "Get Policy Violation Alert Report"
                      DATA={"userKey":"$userKey","requestType":"getProjectAlertsByType","alertType":"REJECTED_BY_POLICY_RESOURCE","projectToken":"$projectToken"}
                      curl --header ${header} --data ${data} ${api} -o ./PolicyViolation.json
                      echo Start Count Policy Vilation Type And Quantity
                      python /PATH/TO/policy_counter.py ./PolicyViolation.json
                      echo curl --header $HEADER --data $DATA $API -o ./PolicyViolation.json
                      #Check Total Quantity Of Policy Violations
                      PATTERN="\"totalRejectedLibraries\":\s*""[0-9]*"
                      POLICY=$(cat ./whitesource/policyRejectionSummary.json | grep -oEi $PATTERN | cut -d ' ' -f 2)
                      if [ $POLICY = 0 ]; then
                        echo Number of policy violations : $POLICY   
                        echo Pass
                      else
                        echo Number of policy violations : $POLICY 
                        echo Policy Violation Please Check The Report
                  fi
                fi
              fi
            fi
          fi
        fi
      fi
    fi
  fi
fi
