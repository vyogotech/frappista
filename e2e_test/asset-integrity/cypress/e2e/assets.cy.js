const assetFailures = [];
const frontendErrors = [];

function installObservers() {
  cy.intercept("GET", "**/assets/**", (req) => {
    req.continue((res) => {
      if (res.statusCode >= 400) {
        assetFailures.push(`${res.statusCode} ${req.url}`);
      }
    });
  });

  cy.on("window:before:load", (win) => {
    win.addEventListener("error", (event) => {
      frontendErrors.push(event.message || String(event.error || "unknown window error"));
    });

    win.addEventListener("unhandledrejection", (event) => {
      const reason = event.reason && event.reason.message ? event.reason.message : String(event.reason || "unknown rejection");
      frontendErrors.push(`unhandledrejection: ${reason}`);
    });
  });
}

function assertHealthyPage(label) {
  cy.document().its("readyState").should("eq", "complete");
  cy.wait(1500);
  cy.then(() => {
    expect(assetFailures, `${label} should not have any failed /assets/ requests`).to.deep.equal([]);
    expect(frontendErrors, `${label} should not have frontend runtime errors`).to.deep.equal([]);
  });
}

describe("asset integrity", () => {
  beforeEach(() => {
    assetFailures.length = 0;
    frontendErrors.length = 0;
    installObservers();
  });

  it("serves all login assets without 404s or frontend errors", () => {
    cy.visit("/login?redirect-to=%2Fdesk");
    cy.location("pathname").should("include", "/login");
    assertHealthyPage("login");
  });

  it("serves all desk assets without 404s or frontend errors", () => {
    cy.request({
      method: "POST",
      url: "/api/method/login",
      form: true,
      body: {
        usr: Cypress.env("ADMIN_USER"),
        pwd: Cypress.env("ADMIN_PASSWORD"),
      },
    }).its("status").should("eq", 200);

    cy.visit("/desk");
    cy.location("pathname").should("include", "/desk");
    assertHealthyPage("desk");
  });
});
