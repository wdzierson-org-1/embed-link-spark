import React from 'react';
import { Link } from 'react-router-dom';

interface LegalSection {
  heading: string;
  body: React.ReactNode;
}

interface LegalPageProps {
  title: string;
  lastUpdated: string;
  intro: string;
  sections: LegalSection[];
}

const LegalPage = ({ title, lastUpdated, intro, sections }: LegalPageProps) => {
  return (
    <div className="min-h-screen bg-background paper-texture">
      <nav className="flex items-center justify-between px-6 py-4 max-w-3xl mx-auto">
        <Link to="/" className="flex items-center space-x-2 hover:opacity-80 transition-opacity">
          <img
            src="/lovable-uploads/2b719fd5-c695-425b-9c8e-71fc6a7f4959.png"
            alt="Stash"
            className="w-8 h-8"
          />
          <span className="text-lg font-tobias text-foreground">Stash</span>
        </Link>
        <Link to="/" className="text-sm font-mori text-muted-foreground hover:text-foreground transition-colors">
          Back to home
        </Link>
      </nav>

      <main className="px-6 py-16 max-w-3xl mx-auto">
        <h1 className="text-4xl md:text-5xl font-tobias font-thin text-foreground mb-3">{title}</h1>
        <p className="text-sm font-mori text-muted-foreground mb-10">Last updated {lastUpdated}</p>

        <p className="text-lg font-mori text-muted-foreground leading-relaxed mb-12">{intro}</p>

        <div className="space-y-10">
          {sections.map(section => (
            <section key={section.heading}>
              <h2 className="text-2xl font-tobias text-foreground mb-3">{section.heading}</h2>
              <div className="font-mori text-muted-foreground leading-relaxed space-y-3">
                {section.body}
              </div>
            </section>
          ))}
        </div>

        <footer className="mt-16 pt-8 border-t border-border">
          <p className="text-sm font-mori text-muted-foreground">
            Questions? Email <a href="mailto:will@dzierson.com" className="underline hover:text-foreground">will@dzierson.com</a>.
          </p>
        </footer>
      </main>
    </div>
  );
};

export default LegalPage;
