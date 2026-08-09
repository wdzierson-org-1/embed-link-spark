import LegalPage from './LegalPage';

const Terms = () => (
  <LegalPage
    title="Terms"
    lastUpdated="August 9, 2026"
    intro="These are the terms for using Stash. The short version: your content is yours, be reasonable, and the service comes with a 7-day free trial before it costs $4.99 a month."
    sections={[
      {
        heading: 'The service',
        body: (
          <p>
            Stash is a personal capture tool: you save links, notes, images, documents, and voice
            recordings, and Stash makes them searchable and answerable. Features may evolve as the
            product improves.
          </p>
        ),
      },
      {
        heading: 'Your content',
        body: (
          <>
            <p>
              Everything you save remains yours. You grant Stash only the license needed to store,
              process, and display it back to you — and, for items you explicitly mark public, to the
              people you share them with.
            </p>
            <p>
              You're responsible for what you save and share. Don't use Stash to store or publish
              content that is illegal or that infringes someone else's rights.
            </p>
          </>
        ),
      },
      {
        heading: 'Billing',
        body: (
          <>
            <p>
              New accounts start with a 7-day free trial. No credit card is required to start; if you
              don't subscribe when the trial ends, your account becomes read-only until you do.
            </p>
            <p>
              The subscription is $4.99/month, billed through Stripe. You can cancel any time from
              Settings, and cancellation takes effect at the end of the current billing period.
            </p>
          </>
        ),
      },
      {
        heading: 'Acceptable use',
        body: (
          <p>
            Don't attempt to disrupt the service, access other people's private content, or use Stash to
            send spam or abuse through its capture channels.
          </p>
        ),
      },
      {
        heading: 'Disclaimers',
        body: (
          <>
            <p>
              Stash is provided as-is. AI-generated titles, descriptions, and answers can be wrong —
              verify anything important against the original source.
            </p>
            <p>
              We work hard to keep your data safe and available, but Stash is not a backup service;
              keep originals of anything irreplaceable.
            </p>
          </>
        ),
      },
      {
        heading: 'Ending things',
        body: (
          <p>
            You can stop using Stash and delete your account at any time. We may suspend accounts that
            violate these terms, with notice where practical.
          </p>
        ),
      },
    ]}
  />
);

export default Terms;
