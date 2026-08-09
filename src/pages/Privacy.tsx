import LegalPage from './LegalPage';

const Privacy = () => (
  <LegalPage
    title="Privacy"
    lastUpdated="August 9, 2026"
    intro="Stash exists to hold things you want to remember — which means we take holding them seriously. This page explains what we collect, what we do with it, and what we will never do with it, in plain language."
    sections={[
      {
        heading: 'What we collect',
        body: (
          <>
            <p>
              Your account information: the email address you sign up with, and a phone number if you
              choose to connect WhatsApp or SMS capture.
            </p>
            <p>
              The content you save: links, notes, images, documents, and voice recordings, along with
              titles, descriptions, and searchable text that Stash generates from them.
            </p>
            <p>
              Basic usage information needed to run the service, such as subscription status and error logs.
            </p>
          </>
        ),
      },
      {
        heading: 'How your content is used',
        body: (
          <>
            <p>
              Your content is used for one purpose: making your own stash useful to you. That includes
              generating titles and descriptions, transcribing audio, extracting text from pages and
              documents, and answering questions you ask about what you've saved.
            </p>
            <p>
              Everything you save is private by default. Content appears publicly only if you explicitly
              mark an item as public.
            </p>
          </>
        ),
      },
      {
        heading: 'Services we rely on',
        body: (
          <>
            <p>Stash runs on a small set of infrastructure providers that process data on our behalf:</p>
            <ul className="list-disc pl-6 space-y-1">
              <li>Supabase — database, authentication, and file storage</li>
              <li>OpenAI — generating descriptions, transcriptions, and answers from your content</li>
              <li>Stripe — payments and subscription management (we never see your card number)</li>
              <li>Twilio — WhatsApp and SMS capture, if you connect a phone number</li>
              <li>Firecrawl — fetching the text of web pages you save</li>
            </ul>
          </>
        ),
      },
      {
        heading: 'What we never do',
        body: (
          <>
            <p>We do not sell your data. We do not show you ads. We do not train AI models on your content.</p>
          </>
        ),
      },
      {
        heading: 'Deleting your data',
        body: (
          <>
            <p>
              Deleting an item removes it and its derived data (descriptions, search indexes) from your
              stash. To delete your entire account and everything in it, email us and we'll take care of
              it promptly.
            </p>
          </>
        ),
      },
    ]}
  />
);

export default Privacy;
