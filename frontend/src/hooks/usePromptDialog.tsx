import { useState, useCallback } from 'react';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';

interface PromptOptions {
  title: string;
  description?: string;
  placeholder?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  required?: boolean;
  initialValue?: string;
  multiline?: boolean;
}

/**
 * Modern, on-brand replacement for the browser's `window.prompt()`.
 * Returns a Promise that resolves to the entered string, or `null` if
 * the user cancelled / closed the dialog.
 */
export function usePromptDialog() {
  const [open, setOpen] = useState(false);
  const [options, setOptions] = useState<PromptOptions>({ title: '' });
  const [value, setValue] = useState('');
  const [resolveRef, setResolveRef] = useState<((v: string | null) => void) | null>(null);

  const prompt = useCallback((opts: PromptOptions): Promise<string | null> => {
    setOptions(opts);
    setValue(opts.initialValue ?? '');
    setOpen(true);
    return new Promise<string | null>((resolve) => {
      setResolveRef(() => resolve);
    });
  }, []);

  const handleConfirm = useCallback(() => {
    if (options.required && !value.trim()) return;
    setOpen(false);
    resolveRef?.(value);
    setResolveRef(null);
  }, [resolveRef, value, options.required]);

  const handleCancel = useCallback(() => {
    setOpen(false);
    resolveRef?.(null);
    setResolveRef(null);
  }, [resolveRef]);

  const PromptDialog = () => (
    <Dialog open={open} onOpenChange={(v) => { if (!v) handleCancel(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{options.title}</DialogTitle>
          {options.description && <DialogDescription>{options.description}</DialogDescription>}
        </DialogHeader>
        <Textarea
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder={options.placeholder}
          rows={options.multiline === false ? 1 : 3}
          autoFocus
        />
        <DialogFooter>
          <Button variant="outline" onClick={handleCancel}>{options.cancelLabel || 'Cancel'}</Button>
          <Button onClick={handleConfirm} disabled={options.required && !value.trim()}>
            {options.confirmLabel || 'Submit'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  return { prompt, PromptDialog };
}
