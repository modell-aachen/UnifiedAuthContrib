import UserCreateComponent from '../dev/UserCreateComponent.vue'
import './mockup_functions/foswiki.js'
import Helpers from './helpers.js'
import 'jasmine-ajax'
import Vue from 'vue'

describe("the UserCreateComponent", () => {
    beforeEach(() => {
        jasmine.Ajax.install();
    });

    it('pass the inputdata correctly', () => {
        let userCreateComponent = Helpers.createVueComponent(UserCreateComponent, {propsData: {propsData: {}}});
        userCreateComponent.$mount();
        userCreateComponent.userData.firstName = "Test";
        userCreateComponent.userData.lastName = "User";
        userCreateComponent.userData.email = "test.user@modell-aachen.de";
        userCreateComponent.generatePassword = true;
        Vue.nextTick(() => {
            userCreateComponent.registerUser();

            let request = jasmine.Ajax.requests.mostRecent();
            jasmine.Ajax.requests.mostRecent().respondWith({
                "status": 200,
                "contentType": 'text/plain',
                "responseText": "Created"
            });

            expect(request.params).toBe("loginName=TestUser&wikiName=TestUser&email=test.user%40modell-aachen.de")
        })
    });
});
