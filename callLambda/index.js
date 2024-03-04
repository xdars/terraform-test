var aws = require('aws-sdk');

var lambda = new aws.Lambda();

const invokeLambda = (lambda, params) => new Promise((resolve, reject) => {
    lambda.invoke(params, (error, data) => {
        if (error) {
            reject(error);
        } else {
            resolve(data);
        }
    });
});

exports.handler = async () => {
    var envFuncName = process.env.AWS_LAMBDA_FUNCTION_NAME;
    var funcName = "prd-make-file-lambda";
    if (envFuncName == 'dev-call-lambda')
        funcName = "dev-make-file-lambda"

    const params = {
        FunctionName: funcName,
    };

    const result = await invokeLambda(lambda, params);

    console.log('Success!');
    console.log(result);

    return {
        statusCode: 500,
        body: JSON.stringify({ message: 'Anyway okay' }),
    };
}
