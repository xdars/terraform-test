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
    const params = {
        FunctionName: 'make_file_lambda',
    };

    const result = await invokeLambda(lambda, params);

    console.log('Success!');
    console.log(result);

    return {
        statusCode: 500,
        body: JSON.stringify({ message: 'Anyway okay' }),
    };
}
