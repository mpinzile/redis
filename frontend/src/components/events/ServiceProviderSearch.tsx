import { useState, useRef, useEffect } from 'react';
import { Input } from '@/components/ui/input';
import { searchApi, type SearchService } from '@/lib/api/search';
import { Loader2, Store } from 'lucide-react';
import { useLanguage } from '@/lib/i18n/LanguageContext';

interface ServiceProviderSearchProps {
  value: string;
  onChange: (name: string) => void;
  placeholder?: string;
}

const ServiceProviderSearch = ({ value, onChange, placeholder = 'Search or type vendor name' }: ServiceProviderSearchProps) => {
  const { t } = useLanguage();
  const [query, setQuery] = useState(value);
  const [results, setResults] = useState<SearchService[]>([]);
  const [loading, setLoading] = useState(false);
  const [showDropdown, setShowDropdown] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>();
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => { setQuery(value); }, [value]);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setShowDropdown(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSearch = (q: string) => {
    setQuery(q);
    onChange(q); // Always update parent with typed value

    if (debounceRef.current) clearTimeout(debounceRef.current);

    if (q.trim().length < 2) {
      setResults([]);
      setShowDropdown(false);
      return;
    }

    debounceRef.current = setTimeout(async () => {
      setLoading(true);
      try {
        const res = await searchApi.searchServices(q, 8);
        if (res.success && res.data?.services) {
          setResults(res.data.services);
          setShowDropdown(res.data.services.length > 0);
        }
      } catch { /* silent */ }
      finally { setLoading(false); }
    }, 300);
  };

  const handleSelect = (service: SearchService) => {
    const name = service.title;
    setQuery(name);
    onChange(name);
    setShowDropdown(false);
  };

  return (
    <div ref={containerRef} className="relative">
      <div className="relative">
        <Input
          value={query}
          onChange={e => handleSearch(e.target.value)}
          onFocus={() => { if (results.length > 0 && query.trim().length >= 2) setShowDropdown(true); }}
          placeholder={placeholder}
        />
        {loading && <Loader2 className="absolute right-2.5 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-muted-foreground" />}
      </div>

      {showDropdown && results.length > 0 && (
        <div className="absolute z-50 w-full mt-1 bg-popover border border-border rounded-md shadow-md max-h-48 overflow-y-auto">
          {results.map(s => (
            <button
              key={s.id}
              type="button"
              className="w-full text-left px-3 py-2 hover:bg-accent flex items-center gap-2 text-sm"
              onClick={() => handleSelect(s)}
            >
              {s.primary_image ? (
                <img src={s.primary_image} alt="" className="w-7 h-7 rounded object-cover flex-shrink-0" />
              ) : (
                <div className="w-7 h-7 rounded bg-muted flex items-center justify-center flex-shrink-0">
                  <Store className="w-3.5 h-3.5 text-muted-foreground" />
                </div>
              )}
              <div className="min-w-0 flex-1">
                <p className="font-medium truncate text-foreground">{s.title}</p>
                {(s.category_name || s.service_type_name) && (
                  <p className="text-xs text-muted-foreground truncate">
                    {s.category_name || s.service_type_name}
                    {s.location ? ` - ${s.location}` : ''}
                  </p>
                )}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

export default ServiceProviderSearch;
