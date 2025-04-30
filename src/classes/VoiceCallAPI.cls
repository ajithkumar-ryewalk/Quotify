@RestResource(urlMapping='/VoiceCallAPI/*')
global with sharing class VoiceCallAPI {

    @HttpPost
    global static String insertVoiceCall() {
        RestRequest req = RestContext.request;
        String reqBody = req.requestBody.toString();

        VoiceCall callRecord = (VoiceCall) JSON.deserialize(reqBody, VoiceCall.class);
        insert callRecord;

        return 'Inserted VoiceCall with ID: ' + callRecord.Id;
    }
}