const fs = require('fs');

function parseStorageFertilizer(inputFilePath, outputFilePath, callback) {
    fs.readFile(inputFilePath, 'utf8', (err, data) => {
        if (err) {
            callback(err, null);
            return;
        }
        
        const accounts = JSON.parse(data)._balances;
        const result = [];

        for (const fertilizerId in accounts) {
            if (accounts.hasOwnProperty(fertilizerId)) {
                const accountData = accounts[fertilizerId];
                const accountArray = [];

                for (const account in accountData) {
                    if (accountData.hasOwnProperty(account)) {
                        const { amount, lastBpf } = accountData[account];
                        accountArray.push([
                            account,
                            parseInt(amount, 16).toString(),
                            parseInt(lastBpf, 16).toString()
                        ]);
                    }
                }

                result.push([
                    parseInt(fertilizerId, 16).toString(),
                    accountArray
                ]);
            }
        }

        fs.writeFile(outputFilePath, JSON.stringify(result, null, 2), (writeErr) => {
            if (writeErr) {
                callback(writeErr, null);
                return;
            }
            callback(null, 'File has been written successfully');
        });
    });
}

const inputFilePath = "./reseed/converts/storage-fertilizer20330000.json";
const outputFilePath = "./reseed/converts/outputs/r5-barn-raise.json";
parseStorageFertilizer(inputFilePath, outputFilePath, (err, message) => {
    if (err) {
        console.error('Error:', err);
        return;
    }
    console.log(message);
});

// module.exports = parseStorageFertilizer;
