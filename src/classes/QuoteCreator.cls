/**
 * @description Creates a Quote with QuoteLineItems and their attributes from JSON input
 * @author Akshaya
 * @date 2025-04-29
 */
public with sharing class QuoteCreator {
    
    /**
     * Creates a new Quote for the specified Opportunity and adds Quote Line Items based on products in JSON input
     * @param opportunityId ID of the Opportunity to create the Quote for
     * @param productsJson JSON string containing products with configuration details
     * @return Id The ID of the newly created Quote
     */
    @InvocableMethod
    public static List<Quote> createQuoteWithLineItems(List<QuoteCreatorRequest> requests) {
        List<Quote> results = new List<Quote>();
        
        for (QuoteCreatorRequest request : requests) {
            results.add(processQuoteCreation(request.opportunityId, request.productsJson, request.quoteId));
        }
        
        return results;
    }
    
    /**
     * Helper method to process quote creation
     * @param opportunityId ID of the Opportunity
     * @param productsJson JSON string of products with configuration
     * @return Id The ID of the newly created Quote
     */
    private static Quote processQuoteCreation(Id opportunityId, String productsJson, Id quoteId) {
    try {
        Object parsedJson = JSON.deserializeUntyped(productsJson);
        List<Map<String, Object>> productConfigList = new List<Map<String, Object>>();
        
        if (parsedJson instanceof List<Object>) {
            for (Object item : (List<Object>) parsedJson) {
                productConfigList.add((Map<String, Object>) item);
            }
        } else if (parsedJson instanceof Map<String, Object>) {
            productConfigList.add((Map<String, Object>) parsedJson);
        } else {
            throw new QuoteCreatorException('Invalid JSON format. Expected a product configuration or a list of configurations.');
        }
        
        if (productConfigList.isEmpty()) {
            throw new QuoteCreatorException('At least one product configuration is required in the JSON input.');
        }

        // Query the Opportunity to get the Pricebook ID
        Opportunity opp = [
            SELECT Id, Pricebook2Id, Name 
            FROM Opportunity 
            WHERE Id = :opportunityId 
            LIMIT 1
        ];
        
        if (opp.Pricebook2Id == null) {
            throw new QuoteCreatorException('Opportunity does not have a Pricebook assigned.');
        }
        Quote newQuote = new Quote();
        if (quoteId == null) {
            // Create the Quote
            newQuote.OpportunityId = opportunityId;
            newQuote.Pricebook2Id = opp.Pricebook2Id;
            newQuote.Name = 'Quote for ' + opp.Name;
            newQuote.Status = 'Draft';
            
            insert newQuote;
            
            // Query the auto-number field (replace AutoNumberField__c with your actual field API name)
            newQuote = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :newQuote.Id];
            
            // Update the Name to include the QuoteNumber field
            newQuote.Name = 'Quote-' + newQuote.QuoteNumber;
            
            update newQuote;
        }
        else {
            newQuote = [SELECT OpportunityId,Pricebook2Id,Name,Status FROM Quote WHERE Id = :quoteId][0];
        }
        for (Map<String, Object> productConfig : productConfigList) {
            // Extract product name and product code
            String productName = productConfig.containsKey('Product Name') ? (String) productConfig.get('Product Name') : (String) productConfig.get('Name');
            String productCode = productConfig.containsKey('Product Code') ? (String) productConfig.get('Product Code') : '';
            String productRecId = productConfig.containsKey('Id') ? (String) productConfig.get('Id') : '';
            if (String.isBlank(productName)) {
                throw new QuoteCreatorException('Product name is required in each JSON product object.');
            }

            // Get quantity or default to 1
            Integer quantity = 1;
            if (productConfig.containsKey('Quantity') && productConfig.get('Quantity') != null) {
                try {
                    quantity = Integer.valueOf(productConfig.get('Quantity'));
                } catch (Exception e) {
                    System.debug('Invalid quantity provided, defaulting to 1');
                }
            }

            // Query the Product by name or code
            List<Product2> products = [
                SELECT Id, Name, ProductCode 
                FROM Product2 
                WHERE Name = :productName 
                OR (ProductCode = :productCode AND ProductCode != null)
                OR Id = :productRecId
                LIMIT 1
            ];
            
            if (products.isEmpty()) {
                throw new QuoteCreatorException('Product not found with name: ' + productName);
            }
            
            Id productId = products[0].Id;
            
            // Query PricebookEntry for the product
            List<PricebookEntry> pricebookEntries = [
                SELECT Id, UnitPrice 
                FROM PricebookEntry 
                WHERE Product2Id = :productId 
                AND Pricebook2Id = :opp.Pricebook2Id
                AND IsActive = true
                LIMIT 1
            ];
            
            if (pricebookEntries.isEmpty()) {
                throw new QuoteCreatorException('No active PricebookEntry found for product: ' + productName);
            }
            
            PricebookEntry pbe = pricebookEntries[0];

            // Create Quote Line Item
            QuoteLineItem qli = new QuoteLineItem(
                QuoteId = newQuote.Id,
                Product2Id = productId,
                PricebookEntryId = pbe.Id,
                UnitPrice = pbe.UnitPrice,
                Quantity = quantity
            );

            insert qli;

            // Create configuration attributes
            createQuoteLineItemAttributes(qli.Id, productId, productConfig);
        }

        return newQuote;
        
    } catch (Exception e) {
        throw new QuoteCreatorException('Error creating quote: ' + e.getMessage());
    }
}

    
    /**
     * Creates QuoteLineItemAttribute records for the given QuoteLineItem
     * @param quoteLineItemId The ID of the QuoteLineItem
     * @param productId The ID of the Product
     * @param productConfig Map containing product configuration
     */
    private static void createQuoteLineItemAttributes(Id quoteLineItemId, Id productId, Map<String, Object> productConfig) {
        // Collect attribute names that need to be queried
        Set<String> attributeNames = new Set<String>();
        Set<String> pickListAttributes = new Set<String>{'Supported Devices','Deployment Type','Support type','License Period'};
        for (String key : productConfig.keySet()) {
            // Skip standard fields and only consider configuration attributes
            if (!key.equals('Product Name') && !key.equals('Product Code') && !key.equals('Quantity')) {
                attributeNames.add(key);
            }
        }
        
        if (attributeNames.isEmpty()) {
            return; // No attributes to create
        }
        
        // Query for AttributeDefinitions by name
        Map<String, Id> attributeDefinitionMap = new Map<String, Id>();
        Map<String, Id> picklistMap = new Map<String, Id>();
        for (AttributeDefinition attr : [
            SELECT Id, Name, PicklistId
            FROM AttributeDefinition 
            WHERE Name IN :attributeNames
        ]) {
            attributeDefinitionMap.put(attr.Name, attr.Id);
            if (attr.PicklistId != null) {
                picklistMap.put(attr.Name, attr.PicklistId);
            }
        }
        Map<String, Id> picklistValueMap = new Map<String, Id>();
        for(AttributePicklistValue pkl : [SELECT Id, Name FROM AttributePicklistValue WHERE PicklistId IN :picklistMap.values()]) {
            picklistValueMap.put(pkl.Name, pkl.Id);
        }

        // Create QuoteLineItemAttribute records
        List<QuoteLineItemAttribute> attributes = new List<QuoteLineItemAttribute>();
        
        for (String attrName : attributeNames) {
            if (attributeDefinitionMap.containsKey(attrName)) {
                String attrValue = String.valueOf(productConfig.get(attrName));
                QuoteLineItemAttribute qliAttr = new QuoteLineItemAttribute();
                if (picklistMap.containsKey(attrName)) {
                    qliAttr.QuoteLineItemId = quoteLineItemId;
                    qliAttr.AttributeDefinitionId = attributeDefinitionMap.get(attrName);
                    qliAttr.AttributeValue = attrValue;
                    qliAttr.AttributePicklistValueId = picklistValueMap.get(attrValue);
                }
                else {
                    qliAttr.QuoteLineItemId = quoteLineItemId;
                    qliAttr.AttributeDefinitionId = attributeDefinitionMap.get(attrName);
                    qliAttr.AttributeValue = attrValue;
                }
                
                attributes.add(qliAttr);
            } else {
                System.debug('Warning: AttributeDefinition not found for attribute: ' + attrName);
            }
        }
        
        if (!attributes.isEmpty()) {
            Database.insertImmediate(attributes);
        }
    }
    
    /**
     * Request wrapper class for invocable method
     */
    public class QuoteCreatorRequest {
        @InvocableVariable(required=true label='Opportunity ID' description='ID of the Opportunity to create the Quote for')
        public Id opportunityId;
        
        @InvocableVariable(required=true label='Products JSON' description='JSON string containing product with configuration details')
        public String productsJson;
        
        @InvocableVariable(required=false label='Quote ID' description='ID of the Quote to add more products')
        public Id quoteId;
    }
    
    public class QuoteCreatorException extends Exception {}
}