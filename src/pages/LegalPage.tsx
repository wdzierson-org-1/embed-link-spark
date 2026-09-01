import StashWordmark from '@/components/StashWordmark';
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
        <Link to="/" className="flex items-center hover:opacity-80 transition-opacity">
          <StashWordmark className="h-5 text-foreground" />
        </Link>
        <Link to="/" className="text-sm font-montreal text-muted-foreground hover:text-foreground transition-colors">
          Back to home
        </Link>
      </nav>

      <main className="px-6 py-16 max-w-3xl mx-auto">
        <h1 className="text-4xl md:text-5xl font-tobias font-thin text-foreground mb-3">{title}</h1>
        <p className="text-sm font-montreal text-muted-foreground mb-10">Last updated {lastUpdated}</p>

        <p className="text-lg font-montreal text-muted-foreground leading-relaxed mb-12">{intro}</p>

        <div className="space-y-10">
          {sections.map(section => (
            <section key={section.heading}>
              <h2 className="text-2xl font-tobias text-foreground mb-3">{section.heading}</h2>
              <div className="font-montreal text-muted-foreground leading-relaxed space-y-3">
                {section.body}
              </div>
            </section>
          ))}
        </div>

        <footer className="mt-16 pt-8 border-t border-border">
          <p className="text-sm font-montreal text-muted-foreground">
            Questions? Email <a href="mailto:will@dzierson.com" className="underline hover:text-foreground">will@dzierson.com</a>.
          </p>
        </footer>
      </main>
    </div>
  );
};

export default LegalPage;
