xml.instruct!
xml.Notification do
		xml.createDateTimeStamp @ideal.timestamp
		xml.transactionID @ideal.transactionID
		xml.purchaseID @ideal.purchaseID
		xml.status @ideal.status
    end
end