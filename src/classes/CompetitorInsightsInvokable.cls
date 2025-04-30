/**
 * @description Invokable Apex class to retrieve competitor insights based on Quote Line Item Attributes
 * @author Generated on 2025-04-25
 */
public with sharing class CompetitorInsightsInvokable {
    
    /**
     * @description Wrapper class to hold the request parameters
     */
    public class CompetitorInsightsRequest {
        @InvocableVariable(label='Quote ID' required=true description='ID of the Quote to retrieve competitor insights for')
        public Id quoteId;
    }
    
    /**
     * @description Wrapper class to hold the response
     */
    public class CompetitorInsightsResponse {
        @InvocableVariable(label='Competitor Insights' description='List of competitor insights matching the product and attributes')
        public List<product_comparison_Heroku_Postgres_C__dlm> competitorInsights;
    }
    
    /**
     * @description Invocable method to find competitor insights based on quote line items
     * @param requests List of CompetitorInsightsRequest
     * @return List of CompetitorInsightsResponse
     */
    @InvocableMethod(label='Get Competitor Insights' description='Retrieves competitor insights based on quote line item attributes')
    public static List<CompetitorInsightsResponse> getCompetitorInsights(List<CompetitorInsightsRequest> requests) {
        List<CompetitorInsightsResponse> responses = new List<CompetitorInsightsResponse>();
        
        for (CompetitorInsightsRequest request : requests) {
            CompetitorInsightsResponse response = new CompetitorInsightsResponse();
            response.competitorInsights = findMatchingCompetitorInsights(request.quoteId);
            responses.add(response);
        }
        
        return responses;
    }
    
    /**
     * @description Helper method to find matching competitor insights
     * @param quoteId The ID of the quote
     * @return List of matching competitor insights
     */
    public static List<product_comparison_Heroku_Postgres_C__dlm> findMatchingCompetitorInsights(Id quoteId) {
        // Map to store the attribute values for each quote line item
        Map<Id, Map<String, String>> quoteLineAttributesMap = new Map<Id, Map<String, String>>();
        
        // First, get all quote line items for the quote
        List<QuoteLineItem> quoteLineItems = [
            SELECT Id, Product2Id, Product2.Name, QuoteId
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
        ];
        
        if (quoteLineItems.isEmpty()) {
            return new List<product_comparison_Heroku_Postgres_C__dlm>();
        }
        
        // Get all quote line item IDs
        Set<Id> quoteLineItemIds = new Set<Id>();
        Map<Id, String> productNameMap = new Map<Id, String>();
        
        for (QuoteLineItem qli : quoteLineItems) {
            quoteLineItemIds.add(qli.Id);
            productNameMap.put(qli.Id, qli.Product2.Name);
            quoteLineAttributesMap.put(qli.Id, new Map<String, String>());
        }
        
        // Query for all attribute values for these quote line items
        List<QuoteLineItemAttribute> attributes = [
            SELECT Id, QuoteLineItemId, AttributeName, AttributeValue
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN :quoteLineItemIds
            AND AttributeName IN ('AI Enabled', 'License Period', 'Supported Devices', 'Support Type', 'Deployment Type','Number of Users')
        ];
        
        // Map the attribute field names to the product_comparison_Heroku_Postgres_C__dlm field names
        Map<String, String> attributeToFieldMap = new Map<String, String>{
            'AI Enabled' => 'ai_enabled__c',
            'License Period' => 'license_period_months__c',
            'Supported Devices' => 'supported_devices__c',
            'Support Type' => 'support_type__c',
            'Deployment Type' => 'deployment_type__c',
            'Number of Users' => 'no_of_users__c'
        };
        
        // Organize the attributes by quote line item
        for (QuoteLineItemAttribute attr : attributes) {
            Map<String, String> attrMap = quoteLineAttributesMap.get(attr.QuoteLineItemId);
            String fieldName = attributeToFieldMap.get(attr.AttributeName);
            if (fieldName != null && attrMap != null) {
                attrMap.put(fieldName, attr.AttributeValue);
            }
        }
        
        // Now find matching competitor insights for each quote line item
        List<product_comparison_Heroku_Postgres_C__dlm> allMatchingInsights = new List<product_comparison_Heroku_Postgres_C__dlm>();
        
        for (Id quoteLineId : quoteLineAttributesMap.keySet()) {
            String productName = productNameMap.get(quoteLineId);
            Map<String, String> attrValues = quoteLineAttributesMap.get(quoteLineId);
            
            // Build dynamic SOQL query for each quote line item
            String query = 'select Id, ai_enabled__c, competitor_company_name__c, competitor_product_name__c, '+
                          'competitor_price__c, product_name__c, no_of_users__c, deployment_type__c,' + 
                          'license_period_months__c, supported_devices__c, support_type__c, product_code__c ' + 
                          'FROM product_comparison_Heroku_Postgres_C__dlm ' +
                           'WHERE product_name__c = :productName';
            
            // Add attribute filters if they have values
            List<String> conditions = new List<String>();
            Map<String, Object> queryParams = new Map<String, Object>{
                'productName' => productName
            };
            
            // Add conditions for each attribute that has a value
            for (String fieldName : attrValues.keySet()) {
            String value = attrValues.get(fieldName);
            if (String.isNotBlank(value)) {
                String paramName = fieldName.replace('__c', '').toLowerCase();
                Object typedValue = value; // default as String
                System.debug('field => '+fieldName);
                if (fieldName == 'ai_enabled__c') {
                    try {
                        typedValue = Boolean.valueOf(value);
                    } catch (Exception e) {
                        continue;
                    }
                } else if (fieldName == 'license_period_months__c' || fieldName == 'no_of_users__c') {
                    try {
                        typedValue = Decimal.valueOf(value);
                    } catch (Exception e) {
                        continue;
                    }
                }
        
                conditions.add(fieldName + ' = :' + paramName);
                queryParams.put(paramName, typedValue);
            }
        }

        
            // Execute the query
            if (!queryParams.isEmpty()) {
                String finalQuery = query + (conditions.isEmpty() ? '' : ' AND ' + String.join(conditions, ' AND '));
                System.debug('SOQL Query Template: ' + finalQuery);
                System.debug('Query Bind Parameters: ' + queryParams);
                String simulatedQuery = finalQuery;
                for (String key : queryParams.keySet()) {
                    Object paramValue = queryParams.get(key);
                    String replacement;
                
                    if (paramValue instanceof String) {
                        replacement = '\'' + ((String)paramValue).replaceAll('\'', '\\\'') + '\'';
                    } else if (paramValue instanceof Boolean || paramValue instanceof Decimal || paramValue instanceof Integer) {
                        replacement = String.valueOf(paramValue);
                    } else {
                        replacement = '\'' + String.valueOf(paramValue).replaceAll('\'', '\\\'') + '\'';
                    }
                
                    simulatedQuery = simulatedQuery.replace(':' + key, replacement);
                }

                System.debug('Simulated SOQL Query (Approximate): ' + simulatedQuery);


                List<product_comparison_Heroku_Postgres_C__dlm> matchingInsights = Database.queryWithBinds(
                    query + (conditions.isEmpty() ? '' : ' AND ' + String.join(conditions, ' AND ')),
                    queryParams,
                    AccessLevel.USER_MODE
                );
                
                allMatchingInsights.addAll(matchingInsights);
            }
        }
        
        return allMatchingInsights;
    }
}