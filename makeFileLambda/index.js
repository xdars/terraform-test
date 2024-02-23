var aws = require('aws-sdk');
var s3 = new aws.S3();

exports.handler = async () => {

    try {
        const timestamp = new Date().toISOString().replace(/:/g, '-').replace(/\..+/, '');

        const filename = `hello-world-${timestamp}.txt`;

        const content = 'Hello, World!';

        const bucketName = 'stourage-ultimately-smoothly-helping-dove';
        const key = filename;

        await s3.putObject({
            Bucket: bucketName,
            Key: key,
            Body: content,
        }).promise();

        const s3Url = `https://${bucketName}.s3.amazonaws.com/${key}`;
        console.log(`File uploaded to S3: ${s3Url}`);

        // Return a success message
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'File uploaded to S3 successfully', s3Url }),
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: 'Error uploading file to S3' }),
        };
    }
};
