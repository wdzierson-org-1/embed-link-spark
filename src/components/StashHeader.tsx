
interface StashHeaderProps {
  itemCount: number;
}

const StashHeader = ({ itemCount }: StashHeaderProps) => {
  return (
    <div className="flex items-center justify-between mb-6">
      <div>
        <h2 className="text-2xl font-bold">Your Stash</h2>
        <p className="text-muted-foreground">
          {itemCount} {itemCount === 1 ? 'item' : 'items'} in your collection
        </p>
      </div>
    </div>
  );
};

export default StashHeader;
